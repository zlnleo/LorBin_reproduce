[CmdletBinding()]
param(
    [string]$RunDirectory,
    [ValidateRange(1, 64)][int]$Threads = 4,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$OutputName = 'checkm2_reproduce',
    [switch]$SkipTestRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

$scriptDir = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptDir
$image = 'quay.io/biocontainers/checkm2:1.0.2--pyh7cba7a3_0'
$expectedArchiveBytes = [int64]1735095758
$expectedArchiveMd5 = 'f35c40f58efaf112d29fc187a88af6f5'
$databaseRoot = Join-Path $projectRoot 'data\checkm2-v2'
$archivePath = Join-Path $databaseRoot 'checkm2_database.tar.gz'

function Invoke-DockerLogged {
    param(
        [string[]]$Arguments,
        [string]$LogPath
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $docker @Arguments 2>&1 | Tee-Object -FilePath $LogPath | Out-Host
        return [int]$LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Assert-Docker {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & $docker info --format '{{.ServerVersion}}' 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw 'Docker engine is unavailable. Start Docker Desktop and retry.'
        }

        $imageId = & $docker image inspect --format '{{.Id}}' $image 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($imageId)) {
            Write-Host "Pulling pinned CheckM2 image: $image"
            & $docker pull $image
            if ($LASTEXITCODE -ne 0) { throw "Docker could not pull $image" }
        }
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

try {
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    if ([string]::IsNullOrWhiteSpace($RunDirectory)) {
        $RunDirectory = Join-Path $projectRoot 'runs\CRR451057_20260928_184541_337_29664'
    }
    $RunDirectory = (Resolve-Path -LiteralPath $RunDirectory -ErrorAction Stop).ProviderPath
    $statusPath = Join-Path $RunDirectory 'status.txt'
    if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) {
        throw "LorBin status file is missing: $statusPath"
    }
    $status = (Get-Content -LiteralPath $statusPath -TotalCount 1).Trim()
    if ($status -ne 'SUCCEEDED') {
        throw "LorBin run is not confirmed SUCCEEDED ($status): $RunDirectory"
    }

    $binsDir = Join-Path $RunDirectory 'result\output_bins'
    if (-not (Test-Path -LiteralPath $binsDir -PathType Container)) {
        throw "Bin directory is missing: $binsDir"
    }
    $bins = @(Get-ChildItem -LiteralPath $binsDir -Filter '*.fa' -File | Sort-Object Name)
    if ($bins.Count -eq 0) { throw "No .fa bins found in $binsDir" }
    $emptyBins = @($bins | Where-Object Length -eq 0)
    if ($emptyBins.Count -gt 0) {
        throw "Empty bin FASTA: $($emptyBins[0].FullName)"
    }

    $checkm2Dir = Join-Path $RunDirectory $OutputName
    if (Test-Path -LiteralPath $checkm2Dir) {
        throw "CheckM2 output already exists; refusing to overwrite: $checkm2Dir"
    }

    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw "CheckM2 v2 archive is missing: $archivePath. Download the 1.0.2-compatible database from Zenodo record 5571251 first."
    }
    $archiveBytes = (Get-Item -LiteralPath $archivePath).Length
    if ($archiveBytes -ne $expectedArchiveBytes) {
        throw "CheckM2 archive is incomplete or is a different version: $archiveBytes bytes; expected $expectedArchiveBytes. Wait for the download to finish."
    }
    Write-Host 'Verifying the CheckM2 v2 archive MD5...'
    $archiveMd5 = (Get-FileHash -LiteralPath $archivePath -Algorithm MD5).Hash.ToLowerInvariant()
    if ($archiveMd5 -ne $expectedArchiveMd5) {
        throw "CheckM2 archive MD5 mismatch: $archiveMd5; expected $expectedArchiveMd5."
    }

    $databaseFiles = @(Get-ChildItem -LiteralPath $databaseRoot -Filter '*.dmnd' -Recurse -File)
    if ($databaseFiles.Count -eq 0) {
        $tar = (Get-Command tar.exe -ErrorAction Stop).Source
        Write-Host 'Extracting the verified CheckM2 v2 database...'
        & $tar -xzf $archivePath -C $databaseRoot
        if ($LASTEXITCODE -ne 0) { throw 'Database archive extraction failed.' }
        $databaseFiles = @(Get-ChildItem -LiteralPath $databaseRoot -Filter '*.dmnd' -Recurse -File)
    }
    if ($databaseFiles.Count -ne 1 -or $databaseFiles[0].Length -eq 0) {
        throw "Expected one nonempty .dmnd file under $databaseRoot; found $($databaseFiles.Count)."
    }
    $databaseFile = $databaseFiles[0]
    Write-Host 'Calculating the extracted database SHA256...'
    $databaseSha256 = (Get-FileHash -LiteralPath $databaseFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $databaseRelative = $databaseFile.FullName.Substring($databaseRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    $containerDatabase = "/db/$databaseRelative"

    Assert-Docker
    $imageId = (& $docker image inspect --format '{{.Id}}' $image).Trim()
    $imageRepoDigests = & $docker image inspect --format '{{json .RepoDigests}}' $image
    $version = (& $docker run --rm $image checkm2 --version).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -ne '1.0.2') {
        throw "Unexpected CheckM2 version in image: $version"
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $testLog = Join-Path $RunDirectory "checkm2_testrun_$stamp.log"
    $predictLog = Join-Path $RunDirectory "checkm2_predict_$stamp.log"
    $dbMount = "type=bind,source=$databaseRoot,target=/db,readonly"
    $binsMount = "type=bind,source=$binsDir,target=/bins,readonly"
    $runMount = "type=bind,source=$RunDirectory,target=/results"
    $testArgs = @('run', '--rm', '--mount', $dbMount,
                  $image, 'checkm2', 'testrun', '--threads', "$Threads",
                  '--lowmem', '--database_path', $containerDatabase)
    $predictArgs = @('run', '--rm', '--mount', $dbMount,
                     '--mount', $binsMount, '--mount', $runMount,
                     $image, 'checkm2', 'predict', '--threads', "$Threads",
                     '--lowmem', '--input', '/bins',
                     '--output-directory', "/results/$OutputName",
                     '--extension', '.fa', '--database_path', $containerDatabase)

    Write-Host "LorBin run: $RunDirectory"
    Write-Host "Bin FASTAs: $($bins.Count)"
    Write-Host "CheckM2: $version; threads: $Threads; low-memory mode: enabled"
    if (-not $SkipTestRun) {
        Write-Host 'Running the built-in CheckM2 test genomes...'
        $testExit = Invoke-DockerLogged -Arguments $testArgs -LogPath $testLog
        if ($testExit -ne 0) {
            throw "CheckM2 testrun failed with exit code $testExit. Log: $testLog"
        }
        if (-not (Select-String -LiteralPath $testLog -SimpleMatch 'Test run successful!' -Quiet)) {
            throw "CheckM2 testrun did not confirm success. Log: $testLog"
        }
    }

    Write-Host 'Evaluating LorBin bin FASTAs with CheckM2...'
    $predictExit = Invoke-DockerLogged -Arguments $predictArgs -LogPath $predictLog
    if ($predictExit -ne 0) {
        throw "CheckM2 predict failed with exit code $predictExit. Log: $predictLog"
    }
    $reportPath = Join-Path $checkm2Dir 'quality_report.tsv'
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        throw "CheckM2 finished without a quality_report.tsv. Log: $predictLog"
    }

    Move-Item -LiteralPath $predictLog -Destination (Join-Path $checkm2Dir 'docker_predict.log')
    if (-not $SkipTestRun) {
        Move-Item -LiteralPath $testLog -Destination (Join-Path $checkm2Dir 'docker_testrun.log')
    }

    $rows = @(Import-Csv -LiteralPath $reportPath -Delimiter "`t")
    if ($rows.Count -ne $bins.Count) {
        throw "CheckM2 report has $($rows.Count) rows for $($bins.Count) input bins. Inspect $reportPath"
    }
    $columns = @($rows[0].PSObject.Properties.Name)
    foreach ($required in @('Name', 'Completeness', 'Contamination')) {
        if ($columns -notcontains $required) {
            throw "CheckM2 report is missing column $required. Inspect $reportPath"
        }
    }
    $expectedNames = @($bins | ForEach-Object BaseName | Sort-Object)
    $reportedNames = @($rows | ForEach-Object { $_.Name -replace '\.fa$', '' } | Sort-Object)
    if (@(Compare-Object -ReferenceObject $expectedNames -DifferenceObject $reportedNames).Count -ne 0) {
        throw "CheckM2 report names do not match the input bins. Inspect $reportPath"
    }

    $high = 0
    $mediumCondition = 0
    $mediumOnly = 0
    foreach ($row in $rows) {
        $completeness = [double]::Parse($row.Completeness, [Globalization.CultureInfo]::InvariantCulture)
        $contamination = [double]::Parse($row.Contamination, [Globalization.CultureInfo]::InvariantCulture)
        if ([double]::IsNaN($completeness) -or [double]::IsInfinity($completeness) -or
            [double]::IsNaN($contamination) -or [double]::IsInfinity($contamination)) {
            throw "Non-finite CheckM2 quality for $($row.Name)."
        }
        $isHigh = $completeness -ge 90 -and $contamination -le 5
        $isMedium = $completeness -ge 50 -and $contamination -lt 10
        if ($isHigh) { $high++ }
        if ($isMedium) { $mediumCondition++ }
        if ($isMedium -and -not $isHigh) { $mediumOnly++ }
    }

    $summary = @(
        'LorBin + CheckM2 1.0.2 single-sample result',
        "LorBin run: $RunDirectory",
        "Input .fa bins: $($bins.Count)",
        "CheckM2 report rows: $($rows.Count)",
        "hBin (completeness >= 90%, contamination <= 5%): $high",
        "mBin condition (completeness >= 50%, contamination < 10%): $mediumCondition",
        "mBin excluding hBin (mutually exclusive): $mediumOnly",
        'The mBin condition includes qualifying hBins.',
        "Raw report: $reportPath"
    )
    $summaryPath = Join-Path $checkm2Dir 'quality_summary.txt'
    $summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    $manifest = @('FileName' + "`t" + 'SizeBytes' + "`t" + 'SHA256')
    foreach ($bin in $bins) {
        $sha256 = (Get-FileHash -LiteralPath $bin.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest += "$($bin.Name)`t$($bin.Length)`t$sha256"
    }
    $manifest | Set-Content -LiteralPath (Join-Path $checkm2Dir 'bins_manifest.tsv') -Encoding UTF8

    $metadata = [ordered]@{
        generated_at = (Get-Date).ToString('o')
        lorbin_run_directory = $RunDirectory
        lorbin_status = $status
        input_bins_directory = $binsDir
        input_bin_count = $bins.Count
        input_total_bytes = ($bins | Measure-Object Length -Sum).Sum
        checkm2_version = $version
        image = $image
        image_id = $imageId
        image_repo_digests = $imageRepoDigests
        database_source = 'https://zenodo.org/records/5571251'
        database_archive = $archivePath
        database_archive_bytes = $archiveBytes
        database_archive_md5 = $archiveMd5
        database_file = $databaseFile.FullName
        database_file_bytes = $databaseFile.Length
        database_file_sha256 = $databaseSha256
        threads = $Threads
        lowmem = $true
        testrun_performed = (-not $SkipTestRun)
        testrun_command_argv = $(if ($SkipTestRun) { $null } else { @($docker) + $testArgs })
        predict_command_argv = @($docker) + $predictArgs
        predict_exit_code = $predictExit
        report_path = $reportPath
        output_directory_name = $OutputName
        report_row_count = $rows.Count
        hbin_count = $high
        mbin_condition_count = $mediumCondition
        mbin_excluding_hbin_count = $mediumOnly
    }
    $metadata | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $checkm2Dir 'provenance.json') -Encoding UTF8

    $summary | ForEach-Object { Write-Host $_ }
    exit 0
} catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
