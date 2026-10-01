# 第一阶段：准备 Python 环境，编译工具不会进入最终镜像。
# 1. 基础系统：使用 Ubuntu 默认官方源。
FROM ubuntu:22.04

# 2. Linux 工具：证书用于 HTTPS，wget 用于下载 Torch。
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 3. Python 环境：dev 和编译器用于安装旧版 Biopython。
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3.10-venv \
    python3.10-dev \
    python3-distutils \
    build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# venv 类似 conda 环境；PATH 让后续命令使用这里的 Python。
RUN python3.10 -m venv /opt/lorbin
ENV PATH="/opt/lorbin/bin:$PATH"
# pip 每次网络等待最多 120 秒，默认使用官方 PyPI。
ENV PIP_DEFAULT_TIMEOUT=120
RUN python -m pip install --no-cache-dir \
    pip==25.2 setuptools==65.5.0 wheel==0.38.4 typing-extensions==4.15.0

# 4. CPU Torch：参照 conda 下载 Miniconda 的写法，下载后校验再安装。
# -c 尝试续传；--tries=20 最多尝试 20 次；--timeout=120 等待上限。
ARG TORCH_SHA256=32fa00d974707c0183bc4dd0c1d69e853d0f15cc60f157b71ac5718847808943
RUN wget -c --tries=20 --timeout=120 \
    -O /tmp/torch-1.11.0+cpu-cp310-cp310-linux_x86_64.whl \
    https://download.pytorch.org/whl/cpu/torch-1.11.0%2Bcpu-cp310-cp310-linux_x86_64.whl \
    && echo "${TORCH_SHA256}  /tmp/torch-1.11.0+cpu-cp310-cp310-linux_x86_64.whl" | sha256sum -c - \
    && python -m pip install --no-cache-dir /tmp/torch-1.11.0+cpu-cp310-cp310-linux_x86_64.whl \
    && rm /tmp/torch-1.11.0+cpu-cp310-cp310-linux_x86_64.whl

# 5. Python 包：-r 表示读取 requirements.txt 中的包名和版本。
COPY docker-light/requirements.txt /tmp/requirements.txt
RUN python -m pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# 6. LorBin：安装项目自带的发行包，然后删除安装包。
COPY LorBin/dist/lorbin-0.1.0.tar.gz /tmp/lorbin-0.1.0.tar.gz
RUN python -m pip install --no-cache-dir /tmp/lorbin-0.1.0.tar.gz \
    && rm /tmp/lorbin-0.1.0.tar.gz

# 第二阶段：从干净系统组装最终镜像。
# 1. 基础系统
FROM ubuntu:22.04

# 2. Linux 工具：只保留运行所需的证书和动态库。
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libgomp1 \
    libstdc++6 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 3. Python 运行环境：这里不需要编译器和开发头文件。
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3-distutils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 4. 生物信息工具：对应 conda 文件中的五个工具。
RUN apt-get update && apt-get install -y --no-install-recommends \
    hmmer \
    prodigal \
    bedtools \
    samtools \
    minimap2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 5. 复制 Python 包和 LorBin；0 表示第一个 FROM 开始的阶段。
COPY --from=0 /opt/lorbin /opt/lorbin
ENV PATH="/opt/lorbin/bin:$PATH"

# 6. 你构建时执行的安装检查，不训练，也不运行 CheckM2。
RUN python --version \
    && python -m pip check \
    && python -c "import torch, numpy, scipy, pandas, sklearn, Bio, joblib; print(torch.__version__); print(torch.ones(2).numpy())" \
    && LorBin --help \
    && samtools --version \
    && minimap2 --version \
    && bedtools --version \
    && hmmsearch -h \
    && prodigal -v

WORKDIR /workspace
CMD ["bash"]
