# syntax=docker/dockerfile:1

# Base image is swappable so the same Dockerfile builds a CPU or a CUDA image.
#   CPU:  BASE_IMAGE=ubuntu:24.04                          (default)
#   CUDA: BASE_IMAGE=nvidia/cuda:12.8.1-runtime-ubuntu24.04 (pair with CUDA_VERSION=12.8 below)
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

# cpu  -> Ubuntu x64 CPU build
# cuda -> Linux x64 CUDA build (needs a matching CUDA base image + nvidia-container-toolkit
#         on the Dokploy host). CUDA_VERSION must match the fork's published binaries
#         (12.4, 12.8 or 13.3) AND have an ubuntu24.04 nvidia/cuda base image tag --
#         12.4.x only ships for ubuntu22.04, so 12.8 is the default here.
ARG LLAMA_BACKEND=cpu
ARG CUDA_VERSION=12.8

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl tar libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/bonsai

# Bonsai 2's ternary GGUF (PQ2_0 / PTQ1_0) needs PrismML's llama.cpp fork -- it adds the
# Hadamard activation transform the packing requires. Stock llama.cpp rejects PTQ1_0/PQ2_0
# outright or, worse, loads Q2_0 with no warning and just produces garbage.
# We resolve the *latest* fork release at build time so the image doesn't go stale.
RUN set -eux; \
    TAG=$(curl -fsSL https://api.github.com/repos/PrismML-Eng/llama.cpp/releases/latest \
          | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/'); \
    case "$LLAMA_BACKEND" in \
        cpu)  PLATFORM="ubuntu-x64" ;; \
        cuda) PLATFORM="linux-cuda-${CUDA_VERSION}-x64" ;; \
        *) echo "Unknown LLAMA_BACKEND: $LLAMA_BACKEND (use cpu or cuda)" >&2; exit 1 ;; \
    esac; \
    URL="https://github.com/PrismML-Eng/llama.cpp/releases/download/${TAG}/llama-${TAG}-bin-${PLATFORM}.tar.gz"; \
    echo "Fetching ${URL}"; \
    curl -fL -o llama.tar.gz "$URL"; \
    mkdir -p bin; \
    tar -xzf llama.tar.gz -C bin --strip-components=1; \
    rm llama.tar.gz

COPY entrypoint.sh /opt/bonsai/entrypoint.sh
RUN chmod +x /opt/bonsai/entrypoint.sh /opt/bonsai/bin/llama-server

ENV MODEL_DIR=/models
VOLUME ["/models"]

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=5 \
    CMD curl -f "http://localhost:${PORT:-8080}/health" || exit 1

ENTRYPOINT ["/opt/bonsai/entrypoint.sh"]