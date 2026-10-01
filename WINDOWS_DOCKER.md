# Windows 命令行运行 LorBin 教程

本教程讲如何从 Windows 启动 Docker、运行 LorBin、查看进度和保存结果。原 `BACKGROUND_RUN.md` 已改名为本文件。

镜像构建命令统一放在 [README](Readme.md)；算法和输出解释见 [TUTORIAL.md](TUTORIAL.md)；BAT 参数和 CheckM2 环境见 [scripts/README.md](scripts/README.md)。下面命令由你手动执行，本文更新时没有运行它们。

## 1. 运行前准备

1. 启动 Docker Desktop，确保 Linux 引擎已就绪。
2. 按 README 构建 `lorbin-hand:v2` 或 `lorbin-light`。
3. 准备 `data/CRR451057.hifiasm.fna` 和 `data/CRR451057.sorted.bam`，两者对应同一份组装。
4. 为数据和结果留出空间。后台运行期间电脑和 Docker 引擎需要保持运行，电脑不能睡眠。

PowerShell 中进入项目并检查引擎：

```powershell
cd D:\project\article\LorBin\handreproduce
docker info --format '{{.OSType}}'
```

应输出 `linux`。仅打开 Docker 窗口不代表引擎已经可用。

## 2. 最省操作的方式：使用已有 BAT

如果使用默认 Conda 镜像和示例输入，直接按 [脚本教程](scripts/README.md)执行预检、后台启动和状态检查。BAT 会自动创建轮次目录和运行记录，不需要自己管理下面的变量。

如果要选择 Light 镜像、修改输入或了解原始命令，使用下面的直接 Docker 方式。

## 3. PowerShell 直接运行 Docker

### 3.1 设置本次运行

在同一个 PowerShell 窗口按顺序执行：

```powershell
$image = 'lorbin-hand:v2'
# 使用 Light 时把上一行改成：$image = 'lorbin-light'
$project = (Get-Location).Path
$dataDir = Join-Path $project 'data'
$runName = "CRR451057_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')_$PID"
$runDir = Join-Path $project "runs\$runName"
$container = "lorbin_$runName"
New-Item -ItemType Directory -Path (Join-Path $project 'runs') -Force | Out-Null
New-Item -ItemType Directory -Path $runDir | Out-Null
Set-Content -LiteralPath (Join-Path $runDir 'status.txt') -Value 'MANUAL' -Encoding UTF8
```

`$runDir` 是本次主机结果目录。每次新实验重新生成这些变量，不覆盖旧结果。`MANUAL` 只标记这是手动启动，没有宣称训练成功。

### 3.2 提交完整流程

**这条命令会启动完整 300 轮训练。** PowerShell 换行符是反引号，反引号后面不要加空格。

```powershell
docker run -d --name $container `
  --mount "type=bind,source=$dataDir,target=/data,readonly" `
  --mount "type=bind,source=$runDir,target=/out" `
  $image LorBin bin `
  -fa /data/CRR451057.hifiasm.fna `
  -b /data/CRR451057.sorted.bam `
  -o /out/result --epoch 300
```

| 写法 | 含义 |
| --- | --- |
| `-d` | 容器在后台运行，提交后终端立即返回 |
| `--name` | 给本次容器起名，方便查日志 |
| 第一个 `--mount` | 把主机输入目录映射为容器 `/data`，只读 |
| 第二个 `--mount` | 把本次主机轮次目录映射为容器 `/out`，可写 |
| `-o /out/result` | 因为 `/out` 已挂载，结果保存到主机 `$runDir\result` |
| `--epoch 300` | 完整 VAE 训练轮数 |

命令返回容器 ID 只说明启动成功，不说明训练已经完成。关闭终端不会停止这个后台容器；关闭 Docker 引擎或让电脑睡眠会影响计算。

### 3.3 看进度并保存状态证据

```powershell
docker logs --tail 50 $container
docker inspect --format '{{.State.Status}} {{.State.ExitCode}}' $container
Get-Content -LiteralPath (Join-Path $runDir 'result\LorBin.log') -Tail 20
```

`running` 表示还在计算。只有 `exited 0` 才表示命令正常退出，还要确认日志有最后一轮记录、所需文件完整，不能只看退出码。

需要持续跟踪可用 `docker logs -f $container`，按 Ctrl+C 退出日志跟踪，容器继续运行。详细训练进度以 `result/LorBin.log` 为准。

运行结束后保存容器配置和状态：

```powershell
docker inspect $container | Out-File -LiteralPath (Join-Path $runDir 'container-inspect.json') -Encoding utf8
Get-ChildItem -LiteralPath (Join-Path $runDir 'result\output_bins') -Filter '*.fa'
```

手动方式不会更新 `runs/latest_run.json`，也不会调用 BAT 的产物检查，因此 BAT 的 `--status` 不会自动查看这一轮。重新打开终端后，使用刚才的实际容器名和实际轮次路径。

### 3.4 接着做 CheckM2

准备好脚本教程要求的镜像和数据库，确认 LorBin 已结束，再明确选择这一轮：

```powershell
.\scripts\run_checkm2.bat -RunDirectory "$runDir" -AllowExistingBins -Threads 4
```

手动轮次的状态是 `MANUAL`，所以需要 `-AllowExistingBins`。它允许评价已保存的 bin，不会把该轮标记为通过 BAT 的成功检查。没有这个选项，脚本会拒绝该状态；无参数自动选择也会跳过它。

结果在 `$runDir\checkm2\origin` 和 `$runDir\checkm2\summary`，先打开 `summary\quality_summary.txt`。详细参数、重复评价和 TSV 查看方法集中在 [scripts/README.md](scripts/README.md)。

## 4. 使用传统 CMD

CMD 的换行符是 `^`，不能照抄 PowerShell 的反引号。下面是与上面等价的另一种启动方式，**会启动一次新的 300 轮实验**；不要两个示例都运行。

```bat
cd /d D:\project\article\LorBin\handreproduce
set "IMAGE=lorbin-hand:v2"
mkdir runs\cmd_run_001
echo MANUAL>runs\cmd_run_001\status.txt
docker run -d --name lorbin_cmd_001 ^
  --mount "type=bind,source=%cd%\data,target=/data,readonly" ^
  --mount "type=bind,source=%cd%\runs\cmd_run_001,target=/out" ^
  %IMAGE% LorBin bin ^
  -fa /data/CRR451057.hifiasm.fna ^
  -b /data/CRR451057.sorted.bam ^
  -o /out/result --epoch 300
```

使用 Light 时，把 `IMAGE` 改为 `lorbin-light`。`cmd_run_001` 和 `lorbin_cmd_001` 是示例名，已有同名目录或容器时先换新名字；不要继续写入旧目录。

查看和评价这一轮：

```bat
docker logs --tail 50 lorbin_cmd_001
docker inspect --format "{{.State.Status}} {{.State.ExitCode}}" lorbin_cmd_001
scripts\run_checkm2.bat -RunDirectory "%cd%\runs\cmd_run_001" -AllowExistingBins -Threads 4
```

最后一条必须等 LorBin 完成并检查输出后再执行。CMD 使用 `%变量%`，PowerShell 使用 `$变量`，两种写法不要混用。

## 5. 结果究竟在哪里

```text
runs/<本次轮次>/
├─ status.txt                     # 手动运行示例为 MANUAL
├─ container-inspect.json         # PowerShell 示例中手动保存
├─ result/
│  ├─ LorBin.log
│  ├─ data.csv / embedding.csv / label.csv / model.pt
│  └─ output_bins/bin.*.fa         # 最终 LorBin 分箱结果
└─ checkm2/
   ├─ origin/quality_report.tsv    # 原始质量估计
   └─ summary/quality_summary.txt  # 先看中文汇总
```

不要把数据 COPY 进镜像，也不要把输出写到未挂载的容器路径。当前示例保留容器供查询，结果则已经通过挂载保存到主机。[Docker 目录挂载说明](https://docs.docker.com/engine/storage/bind-mounts/)

## 6. 阅读源码教程时，怎样进入容器逐步调试

需要执行 TUTORIAL 中的 Linux 子命令时，可先在 PowerShell 新建专门的调试目录，进入交互容器：

```powershell
cd D:\project\article\LorBin\handreproduce
$image = 'lorbin-hand:v2'
$project = (Get-Location).Path
$dataDir = Join-Path $project 'data'
$debugDir = Join-Path $project 'runs\debug_001'
New-Item -ItemType Directory -Path $debugDir | Out-Null
docker run --rm -it `
  --mount "type=bind,source=$dataDir,target=/data,readonly" `
  --mount "type=bind,source=$debugDir,target=/out" `
  $image bash
```

已有 debug_001 时换新目录名；使用 Light 时修改 image。`-it` 让你在容器终端输入命令，`bash` 是 Linux shell。进入后再执行 TUTORIAL 中的 `LorBin generate_data/train/cluster`，结果写在主机调试目录下。

输入 `exit` 离开；`--rm` 删除这个调试容器，已挂载的主机结果仍保留。调试目录不自动产生 SUCCEEDED 状态，也不会自动进入 CheckM2 的轮次选择；它用于逐步理解程序，不能与一键运行的参数和结果直接视为相同。
