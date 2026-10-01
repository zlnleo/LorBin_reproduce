# docker-light 分层与参数说明

本目录解释 Light Dockerfile 的写法。**构建命令统一见 [项目 README](../Readme.md)**，Windows 运行见 [WINDOWS_DOCKER.md](../WINDOWS_DOCKER.md)。本次没有构建或运行这个镜像。

## 1. 按什么顺序构造

最终环境按 **Ubuntu → Linux 工具 → Python → 生信工具 → Python 包和 LorBin** 组织。

| 阶段 | 安装内容 | 为什么这样做 |
| --- | --- | --- |
| 第一个 FROM | 证书、wget、Python、编译工具、Python 包和 LorBin | 旧版 Biopython 可能需要编译，先在这里装好 |
| 第二个 FROM | 干净 Ubuntu、运行动态库、系统 Python、五个生信工具 | 不保留第一阶段的编译器和开发头文件 |
| COPY --from=0 | 复制 `/opt/lorbin` 中安装完成的环境 | 0 表示第一个阶段，不需要 AS 命名 |

第一阶段的 venv 类似独立 conda 环境；第二阶段仍需要系统 Python，因为复制的 venv 依赖它。两个阶段使用相同 Ubuntu 版本。

## 2. 必要参数怎么理解

| 参数 | 用途 |
| --- | --- |
| `--no-install-recommends` | APT 不安装推荐的额外软件 |
| `apt-get clean` 与删除 apt lists | 在同一个 RUN 中清理下载包和索引 |
| `--no-cache-dir` | pip 不保存下载缓存 |
| `-r requirements.txt` | 读取 Python 包名和版本清单 |
| `wget -c --tries=20 --timeout=120` | 尝试续传，最多尝试 20 次，每次网络等待上限 120 秒 |
| `sha256sum -c -` | 按预期哈希校验 Torch 安装包 |

requirements.txt 只是依赖清单，完全可以把这些包手写进 Dockerfile。单独放文件是为了缩短 Dockerfile，方便集中查看和修改版本。

APT 已恢复为普通 `apt-get update && apt-get install`，删除了可选重试参数和手动源配置。Ubuntu 与 pip 使用默认官方源，没有配置中国境内镜像或固定代理端口。

## 3. 为什么 Torch 单独下载

之前出现过下载超时，以及约 169 MB 的文件只下载了约 27 MB 后校验失败。这里沿用 Conda 文件下载 Miniconda 的方式：**下载 → 校验 → 安装 → 删除安装包**。

不能把正确 SHA256 换成报错里的错误值。续传需要服务器支持；整个构建步骤停止或失败后，下次构建不保证接着上次的临时文件下载。

## 4. 哪些内容减少镜像体积

- 最终镜像不安装 Conda，不复制编译器和开发头文件。
- 仅安装 CPU Torch，不安装 LorBin 当前导入代码不需要的 torchvision、torchaudio 和 CUDA。
- APT 缓存和安装包在同一层清理，pip 不保存下载缓存。
- 输入数据和运行结果通过挂载提供，不 COPY 进镜像。

当前构建上下文是项目根目录，生效的是根目录 `.dockerignore`。子目录中名为 `.dockerignore` 的文件不会被这条构建命令自动使用；如采用 Dockerfile 专用忽略文件，其名字应为 `Dockerfile.dockerignore`。

Docker 的宿主机构建缓存用来加快重建，与最终镜像大小不同；`--no-cache` 不会自动让镜像变小。具体体积以你构建后的镜像列表为准。

## 5. 对照 Conda 时注意什么

核心 Python 算法包保留原版本，pip 25.2 用于处理下载恢复和旧包构建。APT 生信工具、Python 补丁版本和数值库构建可能与 Conda 不同。

构建末尾有导入、CPU 张量和 CLI 安装检查；这些不能代替真实数据实验，也不能证明论文质量指标已经复现。Light 的本次构建和结果一致性尚未实测，正式对照方法见 TUTORIAL。
