# Reference candidate only: build manually, then validate against lorbin-hand:v2.
# Build context must be handreproduce/, not docker-light/.
FROM ubuntu:22.04 AS runtime-base

ENV LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# Keep the same Ubuntu release and the input-preparation tools for the first trial.
# Biological tool versions are resolved by apt; record and compare them after build.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    python3.10 \
    python3.10-venv \
    libgomp1 \
    bedtools \
    hmmer \
    prodigal \
    samtools \
    minimap2 \
    && rm -rf /var/lib/apt/lists/*

FROM runtime-base AS builder

# Biopython 1.78 may compile from source on Python 3.10.
# These tools remain in the builder and are excluded from the final stage.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    python3.10-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python3.10 -m venv /opt/lorbin
ENV PATH="/opt/lorbin/bin:$PATH"
RUN python -m pip install pip==22.2.2 setuptools==65.5.0 wheel==0.38.4

COPY docker-light/requirements.txt /tmp/requirements.txt
RUN python -m pip install -r /tmp/requirements.txt

# Install the same package archive as docker-conda/Dockerfile.
# Regenerate the archive and update this hash deliberately when changing LorBin code.
ARG LORBIN_ARCHIVE_SHA256=edb2e20b2042c2ab89c8663028352f5c9c5b5a392685b1bee3b8c85c8c89ecea
COPY LorBin/dist/lorbin-0.1.0.tar.gz /tmp/lorbin-0.1.0.tar.gz
RUN echo "${LORBIN_ARCHIVE_SHA256}  /tmp/lorbin-0.1.0.tar.gz" | sha256sum -c - \
    && python -m pip install --no-deps /tmp/lorbin-0.1.0.tar.gz \
    && python -m pip check

FROM runtime-base AS final
ENV PATH="/opt/lorbin/bin:$PATH"
COPY --from=builder /opt/lorbin /opt/lorbin

# Installation checks only; no LorBin training or CheckM2 prediction during build.
RUN python -m pip check \
    && python -c "import torch, numpy, scipy, pandas, sklearn, Bio, joblib; assert torch.__version__ == '1.11.0+cpu'; assert torch.version.cuda is None" \
    && LorBin --help \
    && bedtools --version \
    && hmmsearch -h \
    && prodigal -v \
    && samtools --version \
    && minimap2 --version

RUN python --version > /opt/lorbin-environment.txt 2>&1 \
    && python -m pip freeze >> /opt/lorbin-environment.txt \
    && dpkg-query -W python3.10 bedtools hmmer prodigal samtools minimap2 libgomp1 >> /opt/lorbin-environment.txt

WORKDIR /work
CMD ["bash"]
