FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    pip \
    conda \

COPY LorBin/lorbin_env.yaml /tmp/lorbin_env.yaml
RUN conda env create -f /tmp/lorbin_env.yaml
RUN conda install -n lorbin_env -c bioconda minimap2
COPY LorBin/dist/lorbin-0.1.0.tar.gz /tmp
RUN conda run -n lorbin_env python -m pip install /tmp/lorbin-0.1.0.tar.gz
WORKDIR /workspace
CMD ["bash"]