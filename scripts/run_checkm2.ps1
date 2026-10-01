<#
.SYNOPSIS
对已经成功完成的 LorBin bins 运行 CheckM2，再自动生成中文 HQ/MQ 汇总。
.DESCRIPTION
本脚本会运行 Docker / CheckM2；不会启动 LorBin 训练。
双击配套 BAT 时窗口会保留执行结果；带参数运行 BAT 时直接返回退出码。
不传 -RunDirectory 时，每次扫描 runs，自动选择 status.txt 第一行为 SUCCEEDED 的最新轮次。
按目录名中的运行时间排序，无法识别时回退到目录修改时间；正在运行或失败的轮次会跳过。
传 -RunDirectory 可以选择其他 run，但该目录 status.txt 第一行必须为 SUCCEEDED。
原训练容器已清除时，可明确指定 -RunDirectory -AllowExistingBins，仅评价已保存的非空 bin，原训练退出码仍为未知。
每次扫描所选 run 的 result/output_bins/*.fa；默认输出根目录为该 run 的 checkm2。
CheckM2 原始文件与 Docker 日志保存到 origin；本地统计和来源记录保存到 summary。
若输出目录已存在，拒绝覆盖；再次评估时请改用 -OutputName checkm2_2。

结果怎么看：
  origin/quality_report.tsv：CheckM2 原始表，每一行是一个 bin。
  origin/docker_predict.log / docker_testrun.log：Docker 执行日志；跳过内置测试时没有后一个文件。
  summary/quality_summary.txt：中文解释与 HQ/MQ/Other 数量，建议先用记事本看这个文件。
  summary/bins_quality.tsv：原始列 + HQ/MQ/Other 分组，可在 Excel 中按 Tab 分列。
  summary/provenance.json / bins_manifest.tsv：本地生成的版本、数据库、参数和输入校验记录。

HQ 与 MQ 的阈值和中文说明集中在 summarize_checkm2.ps1；这里调用同一逻辑。
只想统计已经有的 TSV，请运行 summarize_checkm2.bat，不必再次执行本脚本。
HQ/MQ 是 CheckM2 完整度/污染度代理分组，不能仅凭数量证明完整 MIMAG HQ 或论文复现达标。
.EXAMPLE
.\run_checkm2.ps1 -RunDirectory "D:\project\article\LorBin\handreproduce\runs\YOUR_RUN" -Threads 4
对明确指定的成功 run 评估；替换 YOUR_RUN 为真实目录。
.EXAMPLE
.\run_checkm2.ps1 -OutputName checkm2_2 -SkipTestRun
另建结果目录；SkipTestRun 只跳过 CheckM2 内置测试，不跳过 bins 评估。
#>
[CmdletBinding()]
param(
    [string]$RunDirectory,
    [ValidateRange(1, 64)][int]$Threads = 4,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$OutputName = 'checkm2',
    [switch]$SkipTestRun,
    [switch]$AllowExistingBins
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
# 运行时先把日志写到 run 下的临时路径，避免提前创建 origin 使 CheckM2 拒绝输出目录。
# 预测完成或失败后再归档到 origin；失败时也保留已有日志供排查。
$originDir = $null
$testLog = $null
$predictLog = $null

function Save-CheckM2Logs {
    if ([string]::IsNullOrWhiteSpace($originDir)) { return }
    $logsToSave = @()
    if (-not [string]::IsNullOrWhiteSpace($predictLog) -and (Test-Path -LiteralPath $predictLog -PathType Leaf)) {
        $logsToSave += [pscustomobject]@{ Source = $predictLog; Name = 'docker_predict.log' }
    }
    if (-not [string]::IsNullOrWhiteSpace($testLog) -and (Test-Path -LiteralPath $testLog -PathType Leaf)) {
        $logsToSave += [pscustomobject]@{ Source = $testLog; Name = 'docker_testrun.log' }
    }
    if ($logsToSave.Count -eq 0) { return }
    $null = New-Item -ItemType Directory -Path $originDir -Force
    foreach ($log in $logsToSave) {
        Move-Item -LiteralPath $log.Source -Destination (Join-Path $originDir $log.Name)
    }
}

function Invoke-DockerLogged {
    param(
        [string[]]$Arguments,
        [string]$LogPath
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # Windows PowerShell 5.1 会把正常 stderr 文本包装为 ErrorRecord；
        # 转成纯文本后再记录，避免把 CheckM2 的 INFO 日志误显示为 NativeCommandError。
        # 是否失败仍由下面的 Docker 退出码判断，不因 stderr 出现文本就判断失败。
        & $docker @Arguments 2>&1 | ForEach-Object { $_.ToString() } |
            Tee-Object -FilePath $LogPath | Out-Host
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
            throw 'Docker 的 Linux 引擎不可用。请启动 Docker Desktop，等待 Engine running 后重试；仅打开窗口但引擎尚未就绪也不能运行。'
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
    if ($AllowExistingBins -and [string]::IsNullOrWhiteSpace($RunDirectory)) {
        throw '-AllowExistingBins requires an explicit -RunDirectory; automatic selection only accepts SUCCEEDED runs.'
    }
    if ([string]::IsNullOrWhiteSpace($RunDirectory)) {
        $runsRoot = Join-Path $projectRoot 'runs'
        if (-not (Test-Path -LiteralPath $runsRoot -PathType Container)) {
            throw "LorBin runs directory is missing: $runsRoot"
        }
        $runCandidates = @(
            foreach ($run in Get-ChildItem -LiteralPath $runsRoot -Directory) {
                $candidateStatusPath = Join-Path $run.FullName 'status.txt'
                if (-not (Test-Path -LiteralPath $candidateStatusPath -PathType Leaf)) { continue }
                $candidateStatus = ([string](Get-Content -LiteralPath $candidateStatusPath -TotalCount 1 -Encoding UTF8)).Trim()
                if ($candidateStatus -ne 'SUCCEEDED') { continue }
                $runTime = $run.LastWriteTime
                $parsedTime = [datetime]::MinValue
                if ($run.Name -match '_(\d{8}_\d{6}_\d{3})(?:_\d+)?$' -and
                    [datetime]::TryParseExact($Matches[1], 'yyyyMMdd_HHmmss_fff',
                        [Globalization.CultureInfo]::InvariantCulture,
                        [Globalization.DateTimeStyles]::None, [ref]$parsedTime)) {
                    $runTime = $parsedTime
                }
                [pscustomobject]@{ Directory = $run.FullName; Name = $run.Name; RunTime = $runTime }
            }
        )
        $latestRun = $runCandidates | Sort-Object -Property `
            @{ Expression = 'RunTime'; Descending = $true }, @{ Expression = 'Name'; Descending = $true } |
            Select-Object -First 1
        if ($null -eq $latestRun) {
            throw "No SUCCEEDED LorBin run found in $runsRoot. Complete LorBin first or use -RunDirectory."
        }
        $RunDirectory = $latestRun.Directory
        Write-Host "自动选择最新成功轮次：$($latestRun.Name)"
    }
    $RunDirectory = (Resolve-Path -LiteralPath $RunDirectory -ErrorAction Stop).ProviderPath
    Write-Host "本次 CheckM2 运行目录：$RunDirectory"
    $statusPath = Join-Path $RunDirectory 'status.txt'
    if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) {
        throw "LorBin status file is missing: $statusPath"
    }
    $status = (Get-Content -LiteralPath $statusPath -TotalCount 1).Trim()
    if ($status -ne 'SUCCEEDED' -and -not $AllowExistingBins) {
        throw "LorBin run is not confirmed SUCCEEDED ($status): $RunDirectory"
    }
    if ($status -ne 'SUCCEEDED') {
        Write-Warning "Only saved bin FASTAs will be evaluated. LorBin status is $status; its successful exit is not verified."
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
    $originDir = Join-Path $checkm2Dir 'origin'
    $summaryDir = Join-Path $checkm2Dir 'summary'

    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw "CheckM2 v2 archive is missing: $archivePath. Download the 1.0.2-compatible database from Zenodo record 5571251 first."
    }
    $archiveBytes = (Get-Item -LiteralPath $archivePath).Length
    if ($archiveBytes -ne $expectedArchiveBytes) {
        throw "CheckM2 archive is incomplete or is a different version: $archiveBytes bytes; expected $expectedArchiveBytes. Wait for the download to finish."
    }
    # 先确认 Docker 可运行，避免引擎未启动时仍耗时校验几个 GB 的数据库。
    Assert-Docker
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
                     '--output-directory', "/results/$OutputName/origin",
                     '--extension', '.fa', '--database_path', $containerDatabase)

    Write-Host "LorBin run: $RunDirectory"
    Write-Host "Bin FASTAs: $($bins.Count)"
    Write-Host "原始输出：$originDir"
    Write-Host "本地统计：$summaryDir"
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
    # CheckM2 已返回，此时才可创建/使用 origin 并收纳原始执行日志。
    Save-CheckM2Logs
    $savedPredictLog = Join-Path $originDir 'docker_predict.log'
    if ($predictExit -ne 0) {
        throw "CheckM2 predict failed with exit code $predictExit. Log: $savedPredictLog"
    }
    $reportPath = Join-Path $originDir 'quality_report.tsv'
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        throw "CheckM2 finished without a quality_report.tsv. Log: $savedPredictLog"
    }

    # 独立脚本集中完成 TSV 校验与 HQ/MQ 统计；可单独运行，不需再次调用 Docker。
    $summarizer = Join-Path $scriptDir 'summarize_checkm2.ps1'
    $quality = & $summarizer -ReportPath $reportPath -OutputDirectory $summaryDir `
        -ExpectedBinNames @($bins | ForEach-Object BaseName) -PassThru

    $manifest = @('FileName' + "`t" + 'SizeBytes' + "`t" + 'SHA256')
    foreach ($bin in $bins) {
        $sha256 = (Get-FileHash -LiteralPath $bin.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest += "$($bin.Name)`t$($bin.Length)`t$sha256"
    }
    $manifest | Set-Content -LiteralPath (Join-Path $summaryDir 'bins_manifest.tsv') -Encoding UTF8

    $metadata = [ordered]@{
        generated_at = (Get-Date).ToString('o')
        lorbin_run_directory = $RunDirectory
        lorbin_status = $status
        allow_existing_bins = [bool]$AllowExistingBins
        lorbin_success_confirmed_by_status = ($status -eq 'SUCCEEDED')
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
        output_root = $checkm2Dir
        origin_directory = $originDir
        summary_directory = $summaryDir
        report_row_count = $quality.ReportRowCount
        hbin_count = $quality.HBinCount
        mbin_condition_count = $quality.MBinConditionCount
        mbin_excluding_hbin_count = $quality.MBinExcludingHBinCount
        other_count = $quality.OtherCount
        quality_summary_path = $quality.SummaryPath
        bins_quality_path = $quality.BinsQualityPath
        input_manifest_path = (Join-Path $summaryDir 'bins_manifest.tsv')
    }
    $metadata | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $summaryDir 'provenance.json') -Encoding UTF8

    Write-Host "质量汇总：$($quality.SummaryPath)"
    Write-Host "逐 bin 分组：$($quality.BinsQualityPath)"
    exit 0
} catch {
    $failureMessage = $_.Exception.Message
    try {
        Save-CheckM2Logs
    } catch {
        [Console]::Error.WriteLine("WARNING: Could not archive logs to origin: $($_.Exception.Message)")
    }
    [Console]::Error.WriteLine("ERROR: $failureMessage")
    if (-not [string]::IsNullOrWhiteSpace($originDir) -and (Test-Path -LiteralPath $originDir -PathType Container)) {
        [Console]::Error.WriteLine("Saved CheckM2 files/logs: $originDir")
    }
    exit 1
}
