<#
.SYNOPSIS
读取已有 CheckM2 TSV，输出适合初学者查看的 HQ/MQ 统计；不会运行 Docker、CheckM2 或 LorBin。
.DESCRIPTION
TSV 是“用 Tab 分列的表格”。quality_report.tsv 每一行代表一个 bin，Name 是 bin 名。
Completeness 是完整度估计（%）；Contamination 是污染度估计（%）。数字不是概率。
本脚本按 LorBin 论文使用的两个数字阈值统计：
  HQ / hBin：Completeness >= 90 且 Contamination <= 5。
  mBin condition：Completeness >= 50 且 Contamination < 10；这个条件包含 HQ。
  MQ：满足 mBin condition，但不属于 HQ。因此 HQ + MQ + Other = 总 bin 数。
这些是 CheckM2 完整度/污染度代理分组，不能单独证明完整 MIMAG HQ 标准，也不能证明论文复现达标。

不传 -ReportPath 时，每次扫描 runs，选择最新成功且已有 CheckM2 报告的运行轮次。
只选择 status.txt 第一行为 SUCCEEDED 的轮次；正在运行、失败或没有报告的轮次会跳过。
按轮次目录名中的运行时间排序；不能识别时间时回退到目录修改时间。
同一轮有多个 CheckM2 报告时，选择报告修改时间最新的一份，并打印实际选中的路径。
支持输出目录中的 origin/quality_report.tsv，也兼容旧版平铺 quality_report.tsv。
若报告目录中有 checkm2.log，必须确认 finished successfully 才会自动选择；无日志的旧报告仍兼容。
传 -ReportPath 可以读取 checkm2、历史 checkm2_reproduce 或其他目录的报告。
每次重新读取所选文件当时的内容；报告还在生成时请等 CheckM2 完成再汇总。

默认把两个派生文件写到 summary 文件夹：
  项目 runs 中的报告，统一写到该轮 runs/<轮次>/checkm2/summary。
  项目外的报告：在 origin 中时写到同级 summary；其他路径写到报告目录下面的 summary。
  传 -OutputDirectory 时优先使用该目录，不再自动追加 summary。
  quality_summary.txt：中文解释、总数、HQ、MQ、Other，以及非互斥的 mBin condition 数量。
  bins_quality.tsv：保留报告所有列，并增加每个 bin 的分组与 HQ/MQ/Other 标记（1/0）。
重复运行会覆盖这两个派生文件，方便重新统计；不会改写或删除原始报告。
默认目录若已有其他报告的 provenance.json，会停止并提示指定新 -OutputDirectory，避免混用来源。
需要保存多次汇总时，请用 -OutputDirectory 指定新目录。

建议先用记事本打开 quality_summary.txt，再用 Excel 打开 bins_quality.tsv。
如果 Excel 把所有数据放在一列，用“数据 -> 从文本/CSV”，选 Tab（制表符）为分隔符。
.PARAMETER ReportPath
已有 quality_report.tsv 的路径。相对路径以当前命令窗口目录为准；路径有空格时加双引号。
.PARAMETER OutputDirectory
派生统计的保存目录。项目 runs 中的报告默认写到该轮 checkm2/summary；项目外报告按原目录推定 summary。
显式指定时直接使用该目录，可指定新目录保留旧汇总。
.PARAMETER ExpectedBinNames
供 run_checkm2.ps1 使用：在写汇总前核对 TSV 是否覆盖全部输入 bins（FASTA 的基本名）。
.PARAMETER PassThru
供 run_checkm2.ps1 使用：返回计数和输出路径对象，便于生成 provenance.json。
.EXAMPLE
.\summarize_checkm2.ps1
自动选择最新可统计轮次的已有报告；不启动模型或容器。
.EXAMPLE
.\summarize_checkm2.ps1 -ReportPath "D:\project\article\LorBin\handreproduce\runs\YOUR_RUN\checkm2\origin\quality_report.tsv"
统计明确指定的报告。把 YOUR_RUN 替换为真实目录名。
.EXAMPLE
.\summarize_checkm2.ps1 -ReportPath "D:\results\quality_report.tsv" -OutputDirectory "D:\results\summary_2"
把派生统计另存，原始报告保持不变。
.EXAMPLE
.\summarize_checkm2.ps1 -OutputDirectory "D:\results\latest_summary"
自动选择最新可统计报告，只把汇总另存到指定目录。
#>
[CmdletBinding()]
param(
    [string]$ReportPath,
    [string]$OutputDirectory,
    [string[]]$ExpectedBinNames,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $projectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $runsRoot = Join-Path $projectRoot 'runs'
    $selectionDescription = '手动指定报告；本次读取该路径，不自动切换轮次。'
    # 每次重新扫描，避免 latest_run.json 指向尚未结束的轮次；显式路径优先。
    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        if (-not (Test-Path -LiteralPath $runsRoot -PathType Container)) {
            throw "运行目录不存在：$runsRoot。请先完成运行，或用 -ReportPath 指定已有报告。"
        }
        $runCandidates = @(
            foreach ($run in Get-ChildItem -LiteralPath $runsRoot -Directory) {
                $statusPath = Join-Path $run.FullName 'status.txt'
                if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) { continue }
                $status = ([string](Get-Content -LiteralPath $statusPath -TotalCount 1 -Encoding UTF8)).Trim()
                if ($status -ne 'SUCCEEDED') { continue }
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
        $runCandidates = @($runCandidates | Sort-Object -Property `
            @{ Expression = 'RunTime'; Descending = $true }, @{ Expression = 'Name'; Descending = $true })
        $selectedRun = $null
        foreach ($run in $runCandidates) {
            # 只查看每个输出目录的原始报告，不递归到 summary 或其他中间产物。
            $reports = @(
                foreach ($output in Get-ChildItem -LiteralPath $run.Directory -Directory) {
                    foreach ($candidatePath in @((Join-Path $output.FullName 'origin\quality_report.tsv'),
                                                (Join-Path $output.FullName 'quality_report.tsv'))) {
                        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                            $checkm2Log = Join-Path (Split-Path -Parent $candidatePath) 'checkm2.log'
                            if ((Test-Path -LiteralPath $checkm2Log -PathType Leaf) -and
                                -not (Select-String -LiteralPath $checkm2Log -SimpleMatch 'CheckM2 finished successfully.' -Quiet)) {
                                continue
                            }
                            Get-Item -LiteralPath $candidatePath
                        }
                    }
                }
            )
            if ($reports.Count -eq 0) { continue }
            $latestReport = $reports | Sort-Object -Property `
                @{ Expression = 'LastWriteTime'; Descending = $true }, FullName | Select-Object -First 1
            $ReportPath = $latestReport.FullName
            $selectedRun = $run
            break
        }
        if ($null -eq $selectedRun) {
            throw "runs 下没有可统计的成功轮次：$runsRoot。请确认 CheckM2 已完成生成报告，或用 -ReportPath 指定报告。"
        }
        $selectionDescription = "自动选择最新成功且已有报告的轮次：$($selectedRun.Name)；同轮按报告修改时间选择。"
        Write-Host "本次统计轮次目录：$($selectedRun.Directory)"
    }
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
        throw "报告不存在：$ReportPath。请先完成 CheckM2，或用 -ReportPath 指定已生成的 TSV。"
    }
    $ReportPath = (Resolve-Path -LiteralPath $ReportPath).ProviderPath
    Write-Host $selectionDescription
    Write-Host "本次统计报告：$ReportPath"
    $rows = @(Import-Csv -LiteralPath $ReportPath -Delimiter "`t" -Encoding UTF8)
    if ($rows.Count -eq 0) { throw "报告没有 bin 数据：$ReportPath" }
    $columns = @($rows[0].PSObject.Properties.Name)
    foreach ($required in @('Name', 'Completeness', 'Contamination')) {
        if ($columns -notcontains $required) { throw "报告缺少 $required 列：$ReportPath" }
    }
    foreach ($derived in @('Quality_Group', 'HQ', 'MQ', 'Other', 'mBin_condition')) {
        if ($columns -contains $derived) { throw "报告已有派生列 $derived。请读取原始 quality_report.tsv。" }
    }
    $reportedNames = @($rows | ForEach-Object { $_.Name -replace '\.fa$', '' })
    if (@($reportedNames | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw '报告存在空 bin 名，不能可靠统计。'
    }
    if (@($reportedNames | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
        throw '报告存在重复 bin 名，不能可靠统计。'
    }
    # 从完整运行脚本调用时，先核对输入，避免对缺失或多出的 bin 给出正常统计。
    if ($null -ne $ExpectedBinNames -and $ExpectedBinNames.Count -gt 0) {
        if ($rows.Count -ne $ExpectedBinNames.Count -or
            @(Compare-Object -ReferenceObject @($ExpectedBinNames | Sort-Object) -DifferenceObject @($reportedNames | Sort-Object)).Count -ne 0) {
            throw "报告与输入 bins 的数量或名称不一致，请检查：$ReportPath"
        }
    }

    $high = 0
    $mediumCondition = 0
    $mediumOnly = 0
    $annotatedRows = @(
        foreach ($row in $rows) {
            # 固定小数点解析，避免 Windows 区域设置把 99.98 解释错误。
            $completeness = [double]::Parse($row.Completeness, [Globalization.CultureInfo]::InvariantCulture)
            $contamination = [double]::Parse($row.Contamination, [Globalization.CultureInfo]::InvariantCulture)
            if ([double]::IsNaN($completeness) -or [double]::IsInfinity($completeness) -or
                [double]::IsNaN($contamination) -or [double]::IsInfinity($contamination)) {
                throw "bin $($row.Name) 的质量数值不是有限数字。"
            }
            # 边界请保持一致：完整度 90、污染度 5 算 HQ；污染度 10 不满足 mBin condition。
            $isHigh = $completeness -ge 90 -and $contamination -le 5
            $isMediumCondition = $completeness -ge 50 -and $contamination -lt 10
            $isMediumOnly = $isMediumCondition -and -not $isHigh
            $isOther = -not ($isHigh -or $isMediumOnly)
            if ($isHigh) { $high++ }
            if ($isMediumCondition) { $mediumCondition++ }
            if ($isMediumOnly) { $mediumOnly++ }

            # 新建对象保留原报告各列；只在派生表中增加分组，不修改原 TSV。
            $annotated = [ordered]@{}
            foreach ($column in $columns) { $annotated[$column] = $row.$column }
            $annotated['Quality_Group'] = $(if ($isHigh) { 'HQ' } elseif ($isMediumOnly) { 'MQ' } else { 'Other' })
            $annotated['HQ'] = [int]$isHigh
            $annotated['MQ'] = [int]$isMediumOnly
            $annotated['Other'] = [int]$isOther
            $annotated['mBin_condition'] = [int]$isMediumCondition
            [pscustomobject]$annotated
        }
    )
    $other = $rows.Count - $high - $mediumOnly

    $useDefaultOutput = [string]::IsNullOrWhiteSpace($OutputDirectory)
    if ($useDefaultOutput) {
        $reportDir = Split-Path -Parent $ReportPath
        # 找到报告所属的项目轮次，历史目录的统计也统一收进该轮 checkm2/summary。
        $runFolder = (Get-Item -LiteralPath $ReportPath).Directory
        while ($null -ne $runFolder.Parent -and $runFolder.Parent.FullName -ine $runsRoot) {
            $runFolder = $runFolder.Parent
        }
        if ($null -ne $runFolder.Parent -and $runFolder.Parent.FullName -ieq $runsRoot) {
            $OutputDirectory = Join-Path $runFolder.FullName 'checkm2\summary'
        } elseif ((Split-Path -Leaf $reportDir) -ieq 'origin') {
            # 项目外的 origin 报告仍将统计放到同级 summary。
            $OutputDirectory = Join-Path (Split-Path -Parent $reportDir) 'summary'
        } else {
            # 项目外的普通 TSV，将统计放到 reportDir/summary。
            $OutputDirectory = Join-Path $reportDir 'summary'
        }
    }
    $OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    Write-Host "本次统计输出目录：$OutputDirectory"
    $summaryPath = Join-Path $OutputDirectory 'quality_summary.txt'
    $annotatedPath = Join-Path $OutputDirectory 'bins_quality.tsv'
    # 即使用户误把派生文件作为输入，也不能覆盖当前读取的文件。
    if ($ReportPath -ieq $summaryPath -or $ReportPath -ieq $annotatedPath) {
        throw '输入报告与派生文件路径重合，请使用原始 quality_report.tsv 或另选输出目录。'
    }
    # 默认统计目录中已有正式评价记录时，防止不同报告的统计与溯源混在一起。
    $provenancePath = Join-Path $OutputDirectory 'provenance.json'
    if ($useDefaultOutput -and (Test-Path -LiteralPath $provenancePath -PathType Leaf)) {
        $savedProvenance = Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $sourceProperty = $savedProvenance.PSObject.Properties['report_path']
        if ($null -ne $sourceProperty -and -not [string]::IsNullOrWhiteSpace([string]$sourceProperty.Value) -and
            [string]$sourceProperty.Value -ine $ReportPath) {
            throw "默认统计目录已有其他报告的溯源记录：$OutputDirectory。请用 -OutputDirectory 指定新目录，避免混用来源。"
        }
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $summary = @(
        'LorBin / CheckM2：完整度与污染度统计（代理分组）',
        "统计时间：$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))",
        "选择方式：$selectionDescription",
        "原始报告：$ReportPath",
        "总 bin 数：$($rows.Count)",
        "HQ / hBin：$high（完整度 >= 90%，污染度 <= 5%）",
        "MQ（互斥）：$mediumOnly（完整度 >= 50%，污染度 < 10%，且不属于 HQ）",
        "Other：$other（不满足上述 HQ 或 MQ 条件，不等于一定没有研究价值）",
        "核对：HQ + MQ + Other = $($high + $mediumOnly + $other)",
        "mBin condition：$mediumCondition（完整度 >= 50%，污染度 < 10%；包含 HQ，不能与 HQ 相加）",
        '',
        '怎么看：完整度 95% 表示估计恢复了约 95% 的基因组；污染度 2% 表示估计混入约 2% 的冗余/污染信号。',
        '这些是模型估计，不是精确真值；HQ/MQ 在此只按两个数字统计，不代表完整 MIMAG HQ 标准。',
        '比论文时请核对数据、LorBin 参数、CheckM2 版本与数据库，以及双方阈值是否一致。',
        '单个演示样本得到若干 HQ，并不能直接等同复现论文全部结果。',
        '',
        "逐 bin 分组表：$annotatedPath",
        '先用记事本看本文件；Excel 打开 TSV 时用 Tab（制表符）分列。',
        'Quality_Group 是 HQ/MQ/Other；HQ、MQ、Other 的 1 表示属于该组，0 表示不属于。',
        'mBin_condition 的 1 表示满足论文中该数字条件；其数量包含 HQ。',
        '未传 -ReportPath 时，每次自动选择最新成功且已有报告的轮次；指定路径时只读取指定报告。',
        '重复执行只覆盖派生汇总；-OutputDirectory 可另存统计，原始 TSV 保持不变。'
    )
    # 显式写 UTF-8 BOM，Windows PowerShell 5.1、PowerShell 7、记事本和 Excel 都便于识别中文。
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllLines($summaryPath, [string[]]$summary, $utf8Bom)
    $tsvLines = @($annotatedRows | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation)
    [IO.File]::WriteAllLines($annotatedPath, [string[]]$tsvLines, $utf8Bom)
    $summary | ForEach-Object { Write-Host $_ }
    Write-Host "中文汇总已保存：$summaryPath"

    if ($PassThru) {
        [pscustomobject]@{
            ReportPath = $ReportPath
            ReportRowCount = $rows.Count
            HBinCount = $high
            MBinConditionCount = $mediumCondition
            MBinExcludingHBinCount = $mediumOnly
            OtherCount = $other
            SummaryPath = $summaryPath
            BinsQualityPath = $annotatedPath
        }
    }
} catch {
    if ($PassThru) { throw }
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
