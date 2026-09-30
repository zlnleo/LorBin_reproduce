# LorBin 手工复现

先读 [TUTORIAL.md](TUTORIAL.md)：按执行顺序解释输入、特征、ORF/marker、VAE、DBSCAN、BIRCH、输出和复现验收标准。

原目录结构保持不变，只将运行与统计脚本集中到 `scripts/`：

| 内容 | 位置 |
|---|---|
| 完整教程 | [TUTORIAL.md](TUTORIAL.md)，保留在外层 |
| 本地源码与安装包 | [LorBin/](LorBin/) |
| Docker 配置 | [docker-conda/Dockerfile](docker-conda/Dockerfile) |
| 不用 conda 的候选方案 | [docker-light 评估与手动构建](docker-light/README.md)；尚未构建验收 |
| 输入与独立结果 | `data/`、`runs/` |
| 后台运行与状态查询 | [scripts/run_lorbin_background.bat](scripts/run_lorbin_background.bat)，配套 PS1 在同目录 |
| CheckM2 独立质量评估 | [scripts/run_checkm2.bat](scripts/run_checkm2.bat)，配套 PS1 在同目录 |
| 汇总 CheckM2 报告 | [scripts/summarize_checkm2.py](scripts/summarize_checkm2.py) |
| 三个改进方向 | [improve 总览](../improve/README.md) |

在 PowerShell 中检查输入与已保存结果：

```powershell
Set-Location D:\project\article\LorBin\handreproduce
.\scripts\run_lorbin_background.bat --check
.\scripts\run_lorbin_background.bat --status
.\scripts\run_lorbin_background.bat --logs
```

需要**新开一轮完整 300 epoch 计算**时，才执行：

```powershell
.\scripts\run_lorbin_background.bat
```

脚本从上一级项目目录寻找 `data/` 和 `runs/`。BAT 返回后，容器在后台继续计算；每次启动会创建新的运行目录，并更新 `runs/latest_run.json`。`--status` 和 `--logs` 读取这个指针，它代表**最近启动的一轮，不保证已经成功**。容器被清除后，`--status` 可检查磁盘产物并显示 `OUTPUTS_PRESENT`；此时退出码无法核实，不能将该状态当作 `SUCCEEDED`，`--logs` 会读取保存的 `LorBin.log`。

需要构建新镜像时，构建上下文仍是本目录：

```powershell
docker build -f .\docker-conda\Dockerfile -t lorbin-hand:rebuilt .
```

已核验退出码的 [9 月 28 日基线运行](runs/CRR451057_20260928_184541_337_29664/status.txt)完成 300 轮、退出码为 0，产生 **95 个候选 bin FASTA**。包括你 9 月 29 日的两次计算在内，四次运行的关键 CSV 与模型哈希一致。当前 `runs/latest_run.json` 指向 9 月 29 日 11:42 的运行，其容器已不存在，但磁盘产物通过结构检查。当前 Dockerfile 安装本地 `LorBin/dist/lorbin-0.1.0.tar.gz`；静态对照确认实际模块与 `setup.py` 和指定官方提交在统一换行符后相同，归档另有正常 CLI 不使用的旧备份文件。本机重复性不等于已获得官方同样本结果对照。归档哈希与比较范围见[教程开头](TUTORIAL.md)。

对这次**已有的 95 个 bin**运行 CheckM2；下面命令只做质量评价，不会再次训练 LorBin：

```powershell
Set-Location D:\project\article\LorBin\handreproduce
.\scripts\run_checkm2.bat
```

**CheckM2 默认选择固定路径，不会自动检测最新运行，也不读取 `latest_run.json`。** 不传参数时，它每次都读取已核验退出码的 `runs/CRR451057_20260928_184541_337_29664`。要评价另一轮，明确传入 `-RunDirectory`，该轮 `status.txt` 第一行必须是 `SUCCEEDED`；CheckM2 脚本本身不会刷新 LorBin 状态。

```powershell
.\scripts\run_checkm2.bat -RunDirectory "D:\project\article\LorBin\handreproduce\runs\CRR451057_另一轮目录名"
```

所选目录下的 `result/output_bins/*.fa` **每次调用都会重新扫描**，报告数量、名称及输入哈希按这次实际文件核对；95 仅是当前固定基线的数量。默认输出为 `<所选运行目录>/checkm2_reproduce/`，已存在时脚本停止；再次评价可指定新名字：

```powershell
.\scripts\run_checkm2.bat -RunDirectory "D:\project\article\LorBin\handreproduce\runs\CRR451057_20260928_184541_337_29664" -OutputName checkm2_reproduce_2
```

脚本使用独立的 `quay.io/biocontainers/checkm2:1.0.2--pyh7cba7a3_0` 容器、[DIAMOND 数据库 v2](https://doi.org/10.5281/zenodo.5571251)、4 线程和 `--lowmem`。运行前需下载 `data/checkm2-v2/checkm2_database.tar.gz`；[教程第 7 步](TUTORIAL.md#7-checkm2-独立质量评估)给出精确地址、大小和 MD5，也提供**手动读取最新指针、刷新状态并确认成功**的示例。脚本会核验并自动解压数据库，先运行 CheckM2 内置测试，再评价 bin。最终在所选运行的输出目录查看 `quality_report.tsv`（逐 bin 评分）、`quality_summary.txt`（质量数量汇总）、日志和 `provenance.json`。不加参数时的完整报告路径是 `runs/CRR451057_20260928_184541_337_29664/checkm2_reproduce/quality_report.tsv`；使用 `-OutputName` 后则换成该名字对应的目录。

先前中断的会话在同次运行的 `checkm2/quality_report.tsv` 留有一份原始报告，CheckM2 自身日志显示预测完成，但后续汇总与溯源文件未生成；脚本为你的重跑使用新的 `checkm2_reproduce/` 目录，保留旧报告。**当前具备示例流程跑通与本机重复性的证据；新的 CheckM2 复现结果须等你运行 BAT 并核对报告后才能确认。** 官方 demo 未给出这个单样本的标准质量报告，因此没有“至少 N 个合格 bin”的公开通过线。单样本质量结果可作为三个改进方向的基线；论文总体性能仍需相同跨样本评测。解释见[教程：怎样和官方结果比较](TUTORIAL.md#怎样和官方结果比较)。

不用 conda 的 `docker-light` 方案可行，候选文件与风险评估位于 [docker-light/README.md](docker-light/README.md)。候选使用 Ubuntu 22.04、系统 Python 3.10、pip CPU Torch 1.11.0 与多阶段构建，尚未构建或验收。由你手动执行：

```powershell
Set-Location D:\project\article\LorBin\handreproduce
docker build --platform linux/amd64 --progress=plain -f .\docker-light\Dockerfile -t docker-light:trial .
```

构建后再检验安装、短流程和同输入对照。原后台 BAT 固定使用 `lorbin-hand:v2`，不会自动切换到新镜像；更小的体积也不能代替功能与结果检验。
