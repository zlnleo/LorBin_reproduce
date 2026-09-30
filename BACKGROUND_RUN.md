# LorBin 后台运行教程

以下命令以 `handreproduce/` 为工作目录；运行脚本已收进 `scripts/`。完整流程、产物说明与官方对照方法见 [TUTORIAL.md](TUTORIAL.md)。

在 Windows 上双击 [`run_lorbin_background.bat`](scripts/run_lorbin_background.bat)，或从终端执行：

```bat
.\scripts\run_lorbin_background.bat
```

BAT 会调用同目录的 `run_lorbin_detached.ps1`，检查 Docker、镜像和输入，然后以 **Docker detached 模式**运行 `lorbin-hand:v2` 的 `LorBin bin --epoch 300`。BAT 很快返回；关闭启动窗口不会停止 Docker 容器。请保留 BAT 和 PS1 在同一个 `scripts/` 目录。若已有该脚本启动的容器仍在运行，再次启动会被拒绝，避免误开两轮完整计算。

建议先执行不会训练的预检：

```bat
.\scripts\run_lorbin_background.bat --check
```

输入固定为 `data/CRR451057.hifiasm.fna` 和 `data/CRR451057.sorted.bam`。每次启动都会创建独立的 `runs/CRR451057_<时间戳>_<进程号>/`，并在其中保存 `run-info.json`、`status.txt` 和 `result/`。`runs/latest_run.json` 指向最近一次启动；`runs/` 已从 Git 和 Docker 构建上下文排除。脚本不覆盖旧 `output/`。

## 查看进度与结果

```bat
.\scripts\run_lorbin_background.bat --status
.\scripts\run_lorbin_background.bat --logs
```

`--status` 向 Docker 查询最新容器的运行状态与退出码，并刷新该次运行的 `status.txt`。`--logs` 显示最近 50 行容器日志；详细训练记录在 `result/LorBin.log`。脚本会在容器成功退出后检查 `Epoch: 300` 记录、`data.csv`、`embedding.csv`、`label.csv`、模型文件和至少一个 bin FASTA。Docker 容器在结束后保留，便于检查退出码和日志。

这些是**运行和产物结构检查**。2026-09-28 的一次完整运行已成功结束，记录在 `runs/CRR451057_20260928_184541_337_29664/`，并导出 95 个候选 bin FASTA。高质量 MAG 数量仍需用与论文相容的 CheckM2 版本及数据库独立评估，不能用 `bin.*.fa` 文件数代替。[环境验收与评价说明](../improve/ENVIRONMENT_SMOKE.md)列出了检查范围。
