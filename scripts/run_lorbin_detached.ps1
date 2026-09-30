param(
    [switch]$Check,
    [switch]$Status,
    [switch]$Logs
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptDir
$dataDir = Join-Path $projectRoot 'data'
$fasta = Join-Path $dataDir 'CRR451057.hifiasm.fna'
$bam = Join-Path $dataDir 'CRR451057.sorted.bam'
$runsRoot = Join-Path $projectRoot 'runs'
$image = 'lorbin-hand:v2'
$docker = (Get-Command docker.exe -ErrorAction Stop).Source

function Assert-Inputs {
    if (-not (Test-Path -LiteralPath $fasta -PathType Leaf)) {
        throw "Input FASTA missing: $fasta"
    }
    if (-not (Test-Path -LiteralPath $bam -PathType Leaf)) {
        throw "Input BAM missing: $bam"
    }
    $null = & $docker info --format '{{.ServerVersion}}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker engine is unavailable. Start Docker Desktop and retry.'
    }
    $script:imageId = & $docker image inspect --format '{{.Id}}' $image 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($script:imageId)) {
        throw "Docker image is unavailable: $image"
    }
}

function Assert-BindMount {
    $mount = "type=bind,source=$dataDir,target=/data,readonly"
    $null = & $docker run --rm --mount $mount $image sh -lc 'test -r /data/CRR451057.hifiasm.fna && test -r /data/CRR451057.sorted.bam' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker could not read both input files through the bind mount.'
    }
}

function Get-LatestRun {
    $latestPath = Join-Path $runsRoot 'latest_run.json'
    if (-not (Test-Path -LiteralPath $latestPath -PathType Leaf)) {
        throw "No run is recorded yet: $latestPath"
    }
    return (Get-Content -LiteralPath $latestPath -Raw | ConvertFrom-Json)
}

function Get-OutputCheck {
    param([string]$ResultDirectory)

    $missing = @()
    foreach ($name in @('data.csv', 'embedding.csv', 'label.csv', 'model.pt', 'LorBin.log')) {
        $path = Join-Path $ResultDirectory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $missing += $name
        } elseif ((Get-Item -LiteralPath $path).Length -eq 0) {
            $missing += "$name (empty)"
        }
    }
    $lorbinLog = Join-Path $ResultDirectory 'LorBin.log'
    if ((Test-Path -LiteralPath $lorbinLog -PathType Leaf) -and
        -not (Select-String -LiteralPath $lorbinLog -Pattern 'Epoch:\s*300\b' -Quiet)) {
        $missing += 'Epoch 300 record in LorBin.log'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ResultDirectory 'markers.hmmout') -PathType Leaf)) {
        $missing += 'markers.hmmout'
    }
    $binsDir = Join-Path $ResultDirectory 'output_bins'
    if (Test-Path -LiteralPath $binsDir -PathType Container) {
        $binCount = @(Get-ChildItem -LiteralPath $binsDir -File -Filter 'bin.*.fa').Count
    } else {
        $binCount = 0
        $missing += 'output_bins'
    }
    if ($binCount -eq 0) { $missing += 'bin FASTA files' }
    return [pscustomobject]@{ Missing = $missing; BinCount = $binCount }
}

try {
    if ($Check) {
        Assert-Inputs
        Assert-BindMount
        Write-Host "CHECK PASSED: Docker, $image, and both mounted input files are available."
        Write-Host 'No LorBin training was started.'
        exit 0
    }

    if ($Status -or $Logs) {
        $run = Get-LatestRun
        if ($Logs) {
            $ErrorActionPreference = 'Continue'
            $savedDockerLogs = & $docker logs --tail 50 $run.container_name 2>&1
            $logExit = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($logExit -eq 0) {
                $savedDockerLogs | ForEach-Object { Write-Host $_ }
            } else {
                $savedLog = Join-Path $run.result_directory 'LorBin.log'
                if (Test-Path -LiteralPath $savedLog -PathType Leaf) {
                    Write-Host 'Container logs unavailable; showing the saved LorBin.log.'
                    Get-Content -LiteralPath $savedLog -Tail 50
                    exit 0
                }
                Write-Host 'Neither container logs nor a saved LorBin.log could be read.'
            }
            exit $logExit
        }

        $ErrorActionPreference = 'Continue'
        $raw = & $docker inspect --format '{{.State.Status}}|{{.State.ExitCode}}' $run.container_name 2>$null
        $inspectExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($inspectExit -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
            $outputCheck = Get-OutputCheck -ResultDirectory $run.result_directory
            if ($outputCheck.Missing.Count -eq 0) {
                Write-Host 'OUTPUTS_PRESENT'
                Write-Host "Bin FASTA count: $($outputCheck.BinCount)"
                Write-Host "Result: $($run.result_directory)"
                Write-Host 'Saved outputs pass structural checks, including Epoch 300.'
                Write-Host 'Container is unavailable; its exit code cannot be verified. CheckM2 quality is not included.'
                exit 0
            }
            Write-Host 'OUTPUTS_INCOMPLETE'
            Write-Host ('Missing/empty: ' + ($outputCheck.Missing -join ', '))
            Write-Host 'Container is unavailable; its exit code cannot be verified.'
            exit 1
        }
        $parts = $raw -split '\|', 2
        $dockerState = $parts[0]
        $dockerExit = [int]$parts[1]
        $resultDir = Join-Path $run.run_directory 'result'
        $binCount = 0
        $message = ''
        if ($dockerState -eq 'exited') {
            $outputCheck = Get-OutputCheck -ResultDirectory $resultDir
            $binCount = $outputCheck.BinCount
            if ($dockerExit -eq 0 -and $outputCheck.Missing.Count -eq 0) {
                $verdict = 'SUCCEEDED'
                $message = 'LorBin finished 300 epochs and expected output files exist. CheckM2 quality is not included.'
            } else {
                $verdict = 'FAILED'
                $message = "Docker exit code $dockerExit; missing/empty: " + ($outputCheck.Missing -join ', ')
            }
        } else {
            $verdict = $dockerState.ToUpperInvariant()
            $message = 'Run run_lorbin_background.bat --status again later.'
        }
        $statusText = @(
            $verdict,
            "Container: $($run.container_name)",
            "Docker state: $dockerState",
            "Docker exit code: $dockerExit",
            "Bin FASTA count: $binCount",
            "Result: $resultDir",
            "Message: $message"
        ) -join [Environment]::NewLine
        $statusText | Set-Content -LiteralPath (Join-Path $run.run_directory 'status.txt') -Encoding UTF8
        Write-Host $statusText
        if ($verdict -eq 'FAILED') { exit 1 }
        exit 0
    }

    Assert-Inputs
    Assert-BindMount
    $activeRuns = & $docker ps --filter 'label=org.lorbin.run=handreproduce' --format '{{.Names}}'
    if ($LASTEXITCODE -ne 0) { throw 'Could not check for an already running LorBin container.' }
    if ($activeRuns) { throw "A LorBin run is already active: $($activeRuns -join ', ')" }
    New-Item -ItemType Directory -Path $runsRoot -Force | Out-Null
    $stamp = (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + "_$PID"
    $runDir = Join-Path $runsRoot "CRR451057_$stamp"
    $containerName = "lorbin_CRR451057_$stamp"
    New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
    $runInfo = [ordered]@{
        created_at = (Get-Date).ToString('o')
        run_directory = $runDir
        result_directory = (Join-Path $runDir 'result')
        container_name = $containerName
        container_id = $null
        image = $image
        image_id = $script:imageId
        epoch = 300
        fasta = $fasta
        fasta_bytes = (Get-Item -LiteralPath $fasta).Length
        bam = $bam
        bam_bytes = (Get-Item -LiteralPath $bam).Length
    }
    $infoPath = Join-Path $runDir 'run-info.json'
    $runInfo | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $infoPath -Encoding UTF8

    $dockerArgs = @(
        'run', '-d', '--name', $containerName,
        '--label', 'org.lorbin.run=handreproduce',
        '--mount', "type=bind,source=$dataDir,target=/data,readonly",
        '--mount', "type=bind,source=$runDir,target=/out",
        $image, 'LorBin', 'bin',
        '-fa', '/data/CRR451057.hifiasm.fna',
        '-b', '/data/CRR451057.sorted.bam',
        '-o', '/out/result',
        '--epoch', '300'
    )
    $containerId = & $docker @dockerArgs
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerId)) {
        throw 'docker run -d failed; no LorBin run was started.'
    }
    $runInfo.container_id = $containerId.Trim()
    $runInfo | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $infoPath -Encoding UTF8
    $runInfo | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $runsRoot 'latest_run.json') -Encoding UTF8
    "STARTED`nContainer: $containerName`nStarted: $(Get-Date -Format o)" |
        Set-Content -LiteralPath (Join-Path $runDir 'status.txt') -Encoding UTF8

    Write-Host "Full 300-epoch LorBin run launched in Docker background."
    Write-Host "Container: $containerName"
    Write-Host "Run directory: $runDir"
    Write-Host "Check status: $scriptDir\run_lorbin_background.bat --status"
    Write-Host "Recent logs: $scriptDir\run_lorbin_background.bat --logs"
    Write-Host 'The Docker container continues after this BAT window closes.'
    exit 0
} catch {
    Write-Error $_
    exit 1
}
