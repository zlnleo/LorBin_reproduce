# LorBin Docker 复现

本仓库提供 LorBin 的 Docker 构建配置、Windows 运行教程、源码阅读教程，以及 CheckM2 验证和结果汇总脚本。LorBin 的输入是 **contig FASTA 和排序 BAM**，最终分箱结果是 **bin FASTA**。

## 1. 为什么使用 Docker

LorBin 官方支持和测试的是 Linux 环境，依赖 Python、PyTorch 和多个生信工具。Docker 让 Windows 用户通过命令行运行 Linux 环境，减少手工安装依赖和版本冲突，也便于记录、迁移实验环境。

Docker 是本仓库采用的复现方式；已经有合适 Linux/WSL 环境的用户也可以按官方说明直接安装。Docker 能固定一部分环境，但不能替代输入、参数、版本和结果的核对。[官方 LorBin 仓库](https://github.com/LorMeBioAI/LorBin)

## 2. 两种镜像构建方式

准备 Docker，使用 Linux 容器模式。获取仓库后，进入包含 `LorBin/`、`docker-conda/` 和 `docker-light/` 的目录：

```text
git clone https://github.com/zlnleo/LorBin_reproduce.git
cd LorBin_reproduce
```

本机已有项目的用户直接进入 `handreproduce`，不用再次克隆。两种方式都从该目录构建，最后的 `.` 不能省略。

| 方式 | 文件 | 特点 | 镜像名称 |
| --- | --- | --- | --- |
| Conda | `docker-conda/Dockerfile` | 接近官方 conda 安装流程，便于对照学习 | `lorbin-hand:v2` |
| Light | `docker-light/Dockerfile` | 系统 Python + pip，两阶段排除编译工具，减少环境冗余 | `lorbin-light` |

### 方式一：Conda 构建

```text
docker build --platform linux/amd64 --progress=plain -f docker-conda/Dockerfile -t lorbin-hand:v2 .
```

### 方式二：Light 构建

```text
docker build --platform linux/amd64 --progress=plain -f docker-light/Dockerfile -t lorbin-light .
```

两个 Dockerfile 都安装本仓库的 `LorBin/dist/lorbin-0.1.0.tar.gz`。镜像中不打包输入数据或运行结果；它们通过目录挂载提供。Light 的层级和参数解释见 [docker-light/README.md](docker-light/README.md)。

构建命令正常结束、退出码为 0 且日志完成镜像导出，才表示本次成功。Light 尚未完成本次构建和结果验收，不能把已有 Conda 运行记录当成 Light 的验证结果。APT 工具和数值库构建可能与 Conda 不同，比较结果时需要记录版本。

构建需要访问官方下载站点。配置没有绑定某台电脑的代理端口；VPN 是否接管 Docker 网络需要按本机设置确认。当前 CPU Torch 安装包适用于 Linux amd64；ARM 电脑需要 Docker 支持 amd64 模拟。

## 3. 如何使用

| 你要做什么 | 阅读位置 |
| --- | --- |
| 在 Windows 命令行启动、查看和保存 LorBin 结果 | [WINDOWS_DOCKER.md](WINDOWS_DOCKER.md) |
| 了解每一步输入、输出和源码 | [TUTORIAL.md](TUTORIAL.md)：LorBin 复现与源码阅读教程 |
| 使用 BAT 做 CheckM2 验证、统计 HQ/MQ、查看 TSV | [scripts/README.md](scripts/README.md) |
| 理解 Light 的分层、下载和缓存清理 | [docker-light/README.md](docker-light/README.md) |

先准备官方示例输入。下载入口见 [官方示例数据](https://zenodo.org/records/13883404)，解压后将对应文件放入：

```text
data/CRR451057.hifiasm.fna
data/CRR451057.sorted.bam
```

后台 BAT 固定使用 `lorbin-hand:v2` 和这两份输入。构建 `lorbin-light` 不会自动切换 BAT；使用 Light 或其他输入时，可按 Windows 教程直接执行 Docker 命令。

## 4. 目录说明

| 位置 | 作用 |
| --- | --- |
| `LorBin/` | 官方版本对应的源码和本地安装归档；上游说明保留在 `LorBin/README.md` |
| `docker-conda/`、`docker-light/` | 两种镜像构建配置 |
| `scripts/` | 方便启动 LorBin、进行 CheckM2 验证和汇总结果的脚本 |
| `data/` | 本机输入和 CheckM2 数据库，不随 Git 上传 |
| `runs/<轮次>/result/` | 每次独立 LorBin 实验的输出 |
| `runs/<轮次>/checkm2/origin/` | CheckM2 原始报告与产物 |
| `runs/<轮次>/checkm2/summary/` | 中文统计、逐 bin 分类和来源记录 |
| `output/` | **基于官方 LorBin 版本在本机运行得到的历史输出**；可能保留了多次运行的文件，作为历史参考 |

`output/` 是本地生成结果，并非作者发布的标准答案。新实验使用独立的 `runs/` 目录，避免与历史文件混用。数据、output 和 runs 已在 `.gitignore` 与根目录 `.dockerignore` 中排除；GitHub 上只有配置、源码和文档，克隆后不会自动得到本机历史输出。

## 5. 怎样理解“复现完成”

构建成功代表环境装好；完整运行代表流程跑通；CheckM2 完成代表获得 bin 质量估计。这三件事需要分别验证。文件总数不能代替高质量 MAG 数量，也不能直接证明论文整体性能。

当前保留的 Conda 单样本运行记录包含 95 个候选 bin，已有 CheckM2 汇总为 HQ 5、互斥 MQ 4、Other 86。这是本机记录，不是官方规定的通过门槛。验收层次、对应源码和官方比较方法见 [TUTORIAL.md](TUTORIAL.md)。
