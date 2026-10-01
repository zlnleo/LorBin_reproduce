# 脚本教程：运行环境、CheckM2 验证与结果汇总

本目录的脚本方便完成 **LorBin 运行 → CheckM2 质量预测 → 汇总已有报告**。预测脚本结束后已经自动汇总，统计脚本用于以后重新统计或另存结果。

镜像构建见 [README](../Readme.md)，原始 Windows Docker 命令见 [WINDOWS_DOCKER.md](../WINDOWS_DOCKER.md)，算法与源码见 [TUTORIAL.md](../TUTORIAL.md)。本次只更新说明，没有执行脚本。

## 1. 三个 BAT 分别需要什么环境

| 入口 | 功能 | 主机需要 | Docker 是否必需 |
| --- | --- | --- | --- |
| `run_lorbin_background.bat` | 新开完整 300 轮 LorBin 后台实验，或预检/查状态 | Windows、Windows PowerShell 5.1、docker.exe；默认输入与 `lorbin-hand:v2` | 是，Linux 引擎运行中 |
| `run_checkm2.bat` | 对已有 bin FASTA 预测质量并自动汇总 | Windows、PowerShell 5.1 或 7、docker.exe、CheckM2 数据库 | 是，使用独立 CheckM2 镜像 |
| `summarize_checkm2.bat` | 读取已有 TSV，生成中文数量与逐 bin 分组 | Windows、PowerShell 5.1 或 7、已有原始 TSV | 否，可关闭 Docker |

**三个 BAT 都不要求 Windows 主机安装 Python、Conda、LorBin 或 CheckM2。** 前两个脚本的计算环境在容器中，第三个使用 PowerShell 读取表格。终端提示中的 `(base)` 不是这些 BAT 的必要条件。

配套关系：

```text
run_lorbin_background.bat → run_lorbin_detached.ps1
run_checkm2.bat           → run_checkm2.ps1 → summarize_checkm2.ps1
summarize_checkm2.bat      → summarize_checkm2.ps1
summarize_checkm2.py      → 可选 Python 统计入口，只打印数量
```

BAT 和配套 PS1 要留在同一个 `scripts/` 目录。LorBin BAT 固定调用 Windows PowerShell；另两个优先使用 PowerShell 7，没有时回退到 5.1。CheckM2 和统计 BAT 无参数双击后会暂停显示结果；LorBin BAT 提交后台容器后直接返回。

下面示例在 Windows PowerShell 中执行，先进入项目：

```powershell
cd D:\project\article\LorBin\handreproduce
```

## 2. LorBin 后台入口

先确认镜像 `lorbin-hand:v2` 已构建，输入位于 `data/CRR451057.hifiasm.fna` 和 `data/CRR451057.sorted.bam`。

```powershell
# 预检 Docker、镜像和输入挂载，不训练
.\scripts\run_lorbin_background.bat --check

# 新开一次完整 300 轮训练，需要新实验时才执行
.\scripts\run_lorbin_background.bat

# 查最近启动的一轮，并在结束后刷新状态
.\scripts\run_lorbin_background.bat --status
.\scripts\run_lorbin_background.bat --logs
```

此 BAT 只支持无参数、`--check`、`--status`、`--logs`。镜像、示例输入和 300 轮写在 PS1 中；没有 `-Image` 或 `-Epoch` 参数。需要选择 Light 或自定义输入时，按 Windows 教程直接运行 Docker。

每次新建 `runs/CRR451057_<时间戳>_<进程号>/`，保存 `run-info.json`、`status.txt` 和 `result/`。容器后台运行，关闭启动窗口不停止训练，但电脑和 Docker 引擎需要保持运行。不会自动接着启动 CheckM2。

`--status/--logs` 使用 `runs/latest_run.json`，查看的是**最近启动**，不是最近成功的一轮。训练结束后执行 `--status`，才能把状态刷新为自动 CheckM2 所需的 `SUCCEEDED`。

| 状态 | 含义 |
| --- | --- |
| `STARTED` / `RUNNING` | 已提交或正在运行；旧 STARTED 文件不会自行更新 |
| `SUCCEEDED` | 容器退出码 0，并通过 Epoch 300、必要产物和 bin 文件检查 |
| `FAILED` | 容器失败或产物检查没有通过 |
| `OUTPUTS_PRESENT` | 容器不可查询，但磁盘产物通过结构检查；退出码仍未知，不会自动改成 SUCCEEDED |

`--logs` 可回退到磁盘 `result/LorBin.log`。手动 Docker 启动的轮次不自动登记进此 BAT 的最新指针。

## 3. CheckM2 的准备与执行

### 3.1 必要环境

- Docker Linux 引擎运行中，终端能找到 `docker.exe`。
- 独立镜像：`quay.io/biocontainers/checkm2:1.0.2--pyh7cba7a3_0`。本地没有时脚本尝试拉取，需要联网。
- 已完成的 `runs/<轮次>/result/output_bins/*.fa`，文件必须非空。
- CheckM2 1.0.2 兼容的数据库 v2。脚本不会自动下载数据库。[官方版本说明](https://github.com/chklovski/CheckM2/releases/tag/1.0.2)

数据库按下面位置准备：

```text
data/checkm2-v2/
├─ checkm2_database.tar.gz
└─ CheckM2_database/
   └─ uniref100.KO.1.dmnd
```

从 [数据库下载记录](https://zenodo.org/records/5571251)下载压缩包，保存到上述路径。脚本要求压缩包长度为 `1735095758` 字节、MD5 为 `f35c40f58efaf112d29fc187a88af6f5`。即使已经解压，也要保留压缩包。

没有 `.dmnd` 时脚本用 Windows `tar.exe` 解压；解压后要求恰好一个非空 `.dmnd`。会计算数据库和输入的哈希，某些阶段需要时间且不会持续显示进度。默认 4 线程、lowmem 模式，磁盘还需容纳压缩包、解压数据库、镜像和预测结果。

### 3.2 自动选轮次或指定轮次

```powershell
# 自动选最新成功轮次，默认先内置 testrun，再正式 predict
.\scripts\run_checkm2.bat -Threads 4

# 指定某轮；YOUR_RUN 替换成实际目录名
.\scripts\run_checkm2.bat -RunDirectory ".\runs\YOUR_RUN" -Threads 4

# 对同一轮再次评价，使用新目录，避免覆盖已有结果
.\scripts\run_checkm2.bat -RunDirectory ".\runs\YOUR_RUN" -OutputName checkm2_2 -Threads 4
```

这三条是不同用法，按需要选一条。CheckM2 在前台执行，运行期间保持窗口开启；不会训练 LorBin。

| 参数 | 作用 |
| --- | --- |
| `-RunDirectory` | 指定轮次，默认自动选择 |
| `-Threads` | 默认 4，允许 1–64 |
| `-OutputName` | 轮次内的评价文件夹名，默认 checkm2，允许字母、数字、下划线和短横线 |
| `-SkipTestRun` | 只跳过内置测试，仍对你的 bins 做正式预测 |
| `-AllowExistingBins` | 必须配合显式 RunDirectory；允许评价状态尚未确认成功的已有 bins |

正常要求 `status.txt` 第一行为 `SUCCEEDED`。使用 `-AllowExistingBins` 时仍需要该文件，只是放宽成功状态要求；不会把未知退出码变成成功。手动 Docker 示例使用 `MANUAL` 状态，具体操作见 Windows 教程。

默认输出目录已存在时脚本停止，不会自动覆盖或跳过到其他轮次。先前汇总若已经创建了 `checkm2/summary/`，也可能使 `checkm2/` 被判定为已存在，此时选择新 `-OutputName`。

## 4. 最新选择规则与固定路径

| 入口 | 不指定输入时如何选择 |
| --- | --- |
| LorBin `--status/--logs` | 读取 latest_run.json，最近启动的一轮 |
| `run_checkm2` | 每次扫描 runs，选最新 SUCCEEDED 轮次，不要求已有报告 |
| `summarize_checkm2` | 每次扫描 runs，选最新 SUCCEEDED 且已有可选原始报告的轮次 |

两个 CheckM2 入口按轮次目录名编码的启动时间排序，无法解析时回退到目录修改时间。统计入口同一轮有多份报告时，按报告修改时间选择最新一份。

自动统计兼容 `<评价目录>/origin/quality_report.tsv` 和旧平铺 `<评价目录>/quality_report.tsv`。旁边有 `checkm2.log` 时，须含 `CheckM2 finished successfully.`；无日志的旧报告仍兼容。选定后检查 TSV 结构、bin 名和数值，校验失败会报错，不会承诺自动回退到另一份报告。

**自动选择会每次重新扫描；显式路径是固定输入。** `-RunDirectory` 或 `-ReportPath` 不会自动切换到下一轮。正式预测也不会自动寻找“最新且尚未评价”的轮次。

## 5. 原始结果与汇总保存在哪里

```text
runs/<轮次>/checkm2/
├─ origin/
│  ├─ quality_report.tsv
│  ├─ checkm2.log
│  ├─ docker_predict.log
│  ├─ docker_testrun.log           # 未跳过内置测试时
│  ├─ protein_files/
│  └─ diamond_output/
└─ summary/
   ├─ quality_summary.txt          # 中文总数、HQ/MQ/Other
   ├─ bins_quality.tsv             # 原始列 + 每个 bin 的分类
   ├─ provenance.json              # 版本、数据库、命令和路径
   └─ bins_manifest.tsv            # 输入 FASTA 名称、大小和 SHA256
```

使用 `-OutputName checkm2_2` 时，整套结构位于 `checkm2_2/`。正式预测会核对报告与输入 bin 的数量和名称，并把统计明确写到自己的 `<OutputName>/summary/`。

**先用记事本看 `summary/quality_summary.txt`，再用 Excel 看 `summary/bins_quality.tsv`。** 原始质量表保留在 origin；统计文件不能作为下一次统计的原始输入。

## 6. 只统计已有报告，不使用 Docker

```powershell
# 自动选择已有报告
.\scripts\summarize_checkm2.bat

# 指定输入
.\scripts\summarize_checkm2.bat -ReportPath ".\runs\YOUR_RUN\checkm2\origin\quality_report.tsv"

# 自动选输入，只指定输出目录
.\scripts\summarize_checkm2.bat -OutputDirectory "D:\results\latest_summary"

# 同时指定输入与输出
.\scripts\summarize_checkm2.bat -ReportPath "D:\results\quality_report.tsv" -OutputDirectory "D:\results\summary_2"
```

相对路径以当前终端目录为准，带空格的路径加双引号。指定 ReportPath 时不要求运行状态为 SUCCEEDED，也不要求它位于本项目内，但需要使用已经完成的原始 TSV。

默认输出规则：

- 项目 `runs/<轮次>/` 内的报告统一写入该轮 `checkm2/summary/`，包括来自历史 `checkm2_reproduce` 或自定义评价目录的报告。
- 项目外报告位于 `origin/` 时，写入同级 `summary/`；其他项目外报告写入报告目录下的 `summary/`。
- 显式 `-OutputDirectory` 优先，直接使用指定目录，不追加 summary。

每次重新读取报告，只覆盖 `quality_summary.txt` 和 `bins_quality.tsv`；不修改原始 TSV，也不重新生成预测溯源文件。默认 summary 中若已有其他报告的 provenance.json，会拒绝混用，需指定新输出目录。

## 7. TSV 如何查看，HQ/MQ 如何统计

TSV 是用 Tab 分列的表格，每一行代表一个 bin。Excel 中选择“数据 → 从文本/CSV”，编码选 UTF-8，分隔符选 Tab；不要先四舍五入评分再分类。

| 原始字段 | 初学者如何理解 |
| --- | --- |
| Name | bin 名称 |
| Completeness | 完整度估计，百分数；越高一般越完整 |
| Contamination | 污染/冗余估计，百分数；越低一般越好 |
| Completeness_Model_Used | 此 bin 采用的完整度预测模型 |
| Translation_Table_Used | 基因预测采用的遗传密码表编号 |
| Coding_Density | 编码区域占序列的比例，例如 0.87 约为 87% |
| Contig_N50 | 一半组装长度落在不短于该值的 contig 中，单位 bp |
| Average_Gene_Length | 平均预测蛋白长度，氨基酸数 |
| Genome_Size | 当前 bin 总序列长度，bp，不是推断出的完整基因组长度 |
| GC_Content | GC 比例，例如 0.41 约为 41% |
| Total_Coding_Sequences | 预测编码序列数 |
| Total_Contigs / Max_Contig_Length | contig 数量 / 最长 contig 的 bp 长度 |
| Additional_Notes | 模型附加提示 |

这套脚本的统计口径：

| 分组 | 数字条件 |
| --- | --- |
| HQ / hBin | 完整度 ≥90%，污染度 ≤5% |
| MQ（互斥） | 完整度 ≥50%，污染度 <10%，并排除 HQ |
| Other | 不属于 HQ 或 MQ |
| mBin condition | 完整度 ≥50%，污染度 <10%，包含 HQ，即 HQ+MQ |

例如 95/2 算 HQ，70/3 算 MQ；49.8/3 不算 MQ，70/10 也不算 MQ。**HQ + MQ + Other = 总 bin 数**，不要再把 HQ 加到 mBin condition 上。

`bins_quality.tsv` 的 `Quality_Group` 可直接筛选；HQ、MQ、Other 列的 1 表示属于该组，0 表示不属于。手动核对原始 TSV 时，确认 B 列为完整度、C 列为污染度，再填分类公式：

```text
=IF(AND(B2>=90,C2<=5),"HQ",IF(AND(B2>=50,C2<10),"MQ","Other"))
```

若分类写在 O 列，可用 `=COUNTIF(O:O,"HQ")` 等统计。这里按两个评分分组，不等于完成包含 rRNA/tRNA 等要求的完整 MIMAG 高质量验证；论文复现标准见 TUTORIAL。

## 8. 不同环境下怎么运行

### Windows PowerShell、CMD 和双击

PowerShell 使用上面的 `./scripts` 命令；CMD 用 `scripts\run_checkm2.bat -Threads 4` 或 `scripts\summarize_checkm2.bat`。双击不会改变 BAT 和 PS1 的配套要求。

若 PowerShell 7 的统计 BAT 被执行策略阻止，可以直接对本次进程设置策略，不必改全局设置：

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\summarize_checkm2.ps1
```

只有 Windows Python、没有 Docker 时，可以执行统计 BAT，或用 Python 3.10+ 的补充入口：

```powershell
python .\scripts\summarize_checkm2.py "D:\results\quality_report.tsv"
```

Python 入口只打印数量，不自动选轮次，也不生成中文 TXT 和逐 bin 分类表。

### WSL

BAT 不能作为 Linux shell 脚本直接执行。可以切回 Windows 终端，或者在启用 Windows 互操作的 WSL 中调用 Windows PowerShell：

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'D:\project\article\LorBin\handreproduce\scripts\run_checkm2.ps1' -Threads 4
```

此方式仍使用 Windows 解释器、Windows Docker 和 Windows 路径。不能把 `D:\...` 直接改成 `/mnt/d/...` 传给这些 Windows 脚本。

### 原生 Linux / macOS

当前运行 PS1 使用 `docker.exe`、Windows 路径及 `tar.exe`，不能直接当成原生 Linux/macOS 的运行脚本；仅安装 pwsh 不会自动让它们兼容。已有报告可用标准库 Python 入口统计：

```bash
python3 scripts/summarize_checkm2.py /path/to/quality_report.tsv
```

需要 Python 3.10+，不需要第三方 Python 包。要在原生 Linux/macOS 做 CheckM2，可直接运行等价 Docker 命令。下面从项目根目录执行，替换 YOUR_RUN，准备已解压的数据库，并确保该输出目录尚未使用：

```bash
docker run --rm --platform linux/amd64 \
  --mount "type=bind,source=$PWD/data/checkm2-v2,target=/db,readonly" \
  --mount "type=bind,source=$PWD/runs/YOUR_RUN/result/output_bins,target=/bins,readonly" \
  --mount "type=bind,source=$PWD/runs/YOUR_RUN,target=/results" \
  quay.io/biocontainers/checkm2:1.0.2--pyh7cba7a3_0 \
  checkm2 predict --threads 4 --lowmem --extension .fa \
  --input /bins --output-directory /results/checkm2/origin \
  --database_path /db/CheckM2_database/uniref100.KO.1.dmnd
```

这个模板只执行正式预测，没有复刻 Windows 包装脚本的自动选轮次、内置测试、数据库校验和溯源。ARM 主机需要 Docker 支持 amd64 模拟。之后手动运行 Python 统计。也可以在已安装 CheckM2 的 Linux 环境直接运行其 CLI，但当前 BAT 不会自动切换到本地 Conda 环境。
