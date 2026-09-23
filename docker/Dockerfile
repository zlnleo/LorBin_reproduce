#LorBin Dockerfile
#基于linux系统下进行,最主要原因还是因为生物信息工具只能在linux系统下运行,所以选择ubuntu22.04作为基础镜像
FROM ubuntu:22.04
#更新apt-get源,并且构建安装conda相关的依赖包
#-y: 自动确认安装,--no-install-recommends: 不安装推荐的软件包,以减小镜像体积
#wget: 下载文件
#bzip2: 解压缩文件
#ca-certificates: 证书相关,以防止在下载conda安装包时出现证书问题
#rm -rf /var/lib/apt/lists/* 然后删除apt-get的缓存,以减小镜像体积
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    bzip2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# 3. 安装conda相关的内容
ARG MINICONDA_VERSION=py310_23.11.0-2
ARG MINICONDA_SHA256=35a58b8961e1187e7311b979968662c6223e86e1451191bed2e67a72b6bd0658
RUN wget -O /tmp/miniconda.sh \
    https://repo.anaconda.com/miniconda/Miniconda3-${MINICONDA_VERSION}-Linux-x86_64.sh \
    && echo "${MINICONDA_SHA256}  /tmp/miniconda.sh" | sha256sum -c - \
    && bash /tmp/miniconda.sh -b -p /opt/conda \
    && rm /tmp/miniconda.sh
#设置conda的环境变量,以便在后续的命令中可以直接使用conda命令
ENV PATH="/opt/conda/bin:$PATH"
#构建LorBin相关的conda环境,并且安装相关的依赖包
RUN conda create -y -n lorbin_env \
    python=3.10 \
    pip=22.2.2 \
    setuptools=65.5.0 
# 安装 Bioconda 相关依赖和序列处理工具
RUN conda install -y -n lorbin_env -c bioconda \
    biopython=1.78 \
    hmmer \
    prodigal \
    bedtools \
    samtools \
    minimap2 
#安装cpu pytorch
RUN conda install -y -n lorbin_env -c pytorch \
    pytorch=1.11.0 \
    torchvision=0.12.0 \
    torchaudio=0.11.0 \
    cpuonly 
# 兼容旧版 PyTorch，避免 MKL 2024.1+ 导致 iJIT_NotifyEvent 错误
RUN conda install -y -n lorbin_env -c conda-forge \
    "mkl<2024.1"
#安装其他python modules
RUN conda run -n lorbin_env python -m pip install \
    numpy==1.23.3 \
    scikit-learn==1.1.2 \
    scipy==1.13.1 \
    pandas==2.2.2 \
    joblib==1.4.2

COPY LorBin/dist/lorbin-0.1.0.tar.gz /tmp/lorbin-0.1.0.tar.gz
RUN conda run -n lorbin_env \
    python -m pip install /tmp/lorbin-0.1.0.tar.gz
ENV PATH="/opt/conda/envs/lorbin_env/bin:/opt/conda/bin:$PATH"
RUN python --version \
    && python -c "import torch; print('PyTorch:', torch.__version__)" \
    && LorBin --help \
    && samtools --version \
    && minimap2 --version
WORKDIR /workspace
CMD ["bash"]