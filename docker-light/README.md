# docker-light：不用 conda 的 LorBin 镜像候选

结论：**可行，适合做下一次手动构建试验。** 当前文件经过依赖与源码的静态检查，尚未构建镜像或执行容器测试。这里提供参考 Dockerfile，你可以手动修改、构建；构建完成后再检验功能与结果。候选目录名为 `docker-light/`，建议试验镜像标签为 `docker-light:trial`。

## 为什么可以减小体积

现有 `docker-conda/Dockerfile` 在 Ubuntu 22.04 上先安装 Miniconda 的 base 环境，再建立 `lorbin_env`，还安装 `torchvision` 和 `torchaudio`。目前 LorBin Python 模块没有导入这两个包。候选用系统 Python 3.10 + venv + pip，只保留 CPU Torch；编译工具放在 builder 阶段，最终镜像只复制已安装的 venv。[Docker 多阶段构建说明](https://docs.docker.com/build/building/multi-stage/)

现有镜像之前测得约 5.41 GB。候选有明确的缩减来源，但尚不能给出实测体积或缩减百分比。PyTorch、NumPy、SciPy 等运行库仍占空间，不能指望它变成只有几十 MB 的镜像。镜像较小也不代表训练更快或质量更高。

FASTA、BAM、runs 和 CheckM2 数据库已被 `handreproduce/.dockerignore` 排除；旧 Dockerfile 也只复制 LorBin 安装归档。因此本次优先精简环境，不应把原始输入或最终结果打进镜像。CheckM2 继续使用独立容器和外部数据库。

| 方案 | 体积优化方式 | 适合的用途 |
|---|---|---|
| 保留当前 conda 镜像 | 已有成功结果，作为对照保留 | 已验证的基线 |
| 精简 conda 镜像 | 单一环境、移除未使用包、多阶段仅复制可运行环境 | 尽量减少依赖来源变化 |
| 本次无 conda 候选 | 系统 Python + venv + pip + apt，多阶段排除编译工具 | 你准备进行的轻量部署试验，需额外核对工具与数值库 |

Conda 并非不能做小镜像；当前冗余环境和所选二进制库更直接影响体积。无 conda 方案把生物工具的依赖管理交给 apt，把 Python 依赖管理交给 pip，需要更明确地记录和验证版本。

## 这份候选保留什么

| 项目 | 候选设计 | 后续须核对的差异 |
|---|---|---|
| Linux | Ubuntu 22.04，保持旧构建的系统发行版 | 基础镜像标签会更新，验收后应记录 digest |
| Python | 系统 Python 3.10 + `/opt/lorbin` venv | apt 的 Python 补丁版本未必等于旧镜像的 3.10.21 |
| PyTorch | 官方 `1.11.0+cpu` CPython 3.10 / x86_64 wheel | pip 与 conda 的底层数值库构建不同 |
| 科学计算 | NumPy 1.23.3、SciPy 1.13.1、scikit-learn 1.1.2、pandas 2.2.2、joblib 1.4.2 | 直接版本对齐；传递依赖在构建后用 `pip freeze` 记录 |
| FASTA 解析 | Biopython 1.78 | 老版本可能需编译，故保留 builder 中的 gcc 与 Python 头文件 |
| 分箱工具 | bedtools、Prodigal、HMMER | apt 版本与旧 conda 版本未证明一致；重点比较 coverage 和 marker |
| 输入前处理 | samtools、minimap2 | 第一版保留教程的 reads→BAM 能力；已有 BAM 的 `LorBin bin` 不直接调用它们 |
| LorBin | 同一份 `LorBin/dist/lorbin-0.1.0.tar.gz` | 保持代码包一致，先单独比较环境差异 |

[PyTorch 官方历史版本页](https://pytorch.org/get-started/previous-versions/)提供 1.11.0 的 CPU pip 安装方式；[官方 CPU wheel 索引](https://download.pytorch.org/whl/cpu/torch/)有本候选使用的 CPython 3.10 Linux x86_64 wheel，`requirements.txt` 固定其 URL 与 SHA-256。这是 CPU、amd64 试验方案。

**不能删掉 Prodigal 和 HMMER。** 即使参数使用 `no_markers`，`LorBin bin` 仍会先计算 marker；源码调用链为 `lorbin.py:generate_markers()` → `utils.py:generate_markers()` → Prodigal → `hmmsearch`。coverage 则由 `generate_coverage.py` 调用 `bedtools genomecov`。

当前安装归档的 SHA-256 为：

```text
edb2e20b2042c2ab89c8663028352f5c9c5b5a392685b1bee3b8c85c8c89ecea
```

候选继续安装现有 Dockerfile 引用的同一个归档，以便先检验同一份代码在两种环境中的行为。静态对照确认 13 个实际 Python 模块及 `setup.py` 在本地源码、归档和指定官方提交之间一致（统一换行符后）；归档额外含正常 CLI 不使用的旧备份 `lorbin copy.py`。`lorbin.py` 中的 `generate_cluster()` 临时 stub、`bin_length` 回退和新增 CLI 参数也存在于指定官方提交，不能仅凭这些内容认定是本地修改。后续还应核对两份实际镜像中的安装代码。如果你只修改 `LorBin/lorbin/*.py` 而没有重新制作归档，这两份 Dockerfile 都不会自动安装修改后的源码。

## 你手动构建

在 PowerShell 中执行，最后的 `.` 必须是 `handreproduce/` 构建上下文：

```powershell
Set-Location D:\project\article\LorBin\handreproduce
docker build --platform linux/amd64 --progress=plain -f .\docker-light\Dockerfile -t docker-light:trial .
```

Dockerfile 的构建检查只验证安装、Python 导入、CLI 和工具版本，不训练 VAE，也不运行 CheckM2。如果构建失败，保留对应错误；尤其关注旧 wheel 下载、Biopython 编译和 apt 包是否可取得。

构建成功后可保存基本信息，或告知已经构建好，再由我检查：

```powershell
docker image inspect docker-light:trial --format '{{.Id}} {{.Size}}'
docker history docker-light:trial
docker run --rm docker-light:trial cat /opt/lorbin-environment.txt
```

现有 `scripts/run_lorbin_background.bat` 的配套 PS1 仍固定使用 `lorbin-hand:v2`。仅构建 `docker-light:trial` 不会让该 BAT 自动切换镜像。候选检验通过后再明确选择新镜像运行，避免把旧镜像的结果误记到轻量镜像名下。

## 构建后的检验顺序

1. **安装与资源完整性**：核对镜像 ID、体积、Python/包/工具版本，确认无 conda，`pip check` 通过，模型 `.pt` 和 `marker.hmm` 能读取，预训练模型能加载。
2. **短流程功能检查**：验证文件挂载、k-mer、coverage、ORF、marker、VAE 一次训练/编码以及 DBSCAN/BIRCH/FASTA 导出；只用短 smoke test，先不跑 300 轮。`LorBin --help` 通过不足以证明全部功能。
3. **同代码环境对照**：用同一 FASTA/BAM 比较特征的 contig ID、行数、数值及 marker 命中；复用同一份已存在的 embedding 比较聚类成员。标签编号可变化，要比较每组 contig 的成员。
4. **由你运行完整实验**：等功能和对照通过后，用独立目录运行相同 300 轮设置，再用相同 CheckM2 1.0.2 + 数据库 v2 比较逐 bin 质量、高/中质量数量、运行时间与峰值内存。

pip 与 conda 的 BLAS/OpenMP 构建、Python 补丁版本以及 apt 生物工具版本可能造成差异；多尺度聚类也可能放大边界附近的浮点变化。验收时先查明变化来源，不能只凭镜像更小或导出同样数量的 FASTA 判定复现一致。通过后固定基础镜像 digest、apt 版本和完整 Python 依赖清单；这份候选目前还不是已验收的复现镜像。
