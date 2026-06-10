ARG DATUS_VERSION=0.3.3
ARG USE_CN_MIRROR=false
ARG BASE_IMAGE=python:3.12-slim
ARG HF_MIRROR_ENDPOINT=https://huggingface.co

FROM ${BASE_IMAGE}

WORKDIR /app

ARG USE_CN_MIRROR
ARG DATUS_VERSION
ARG HF_MIRROR_ENDPOINT

# Route apt through the Aliyun Debian mirror when USE_CN_MIRROR=true so package
# fetches succeed in regions where deb.debian.org is unreachable.
RUN set -eux; \
    if [ "${USE_CN_MIRROR}" = "true" ]; then \
        if [ -f /etc/apt/sources.list ]; then \
            sed -i 's|http://deb.debian.org|https://mirrors.aliyun.com|g; s|http://security.debian.org|https://mirrors.aliyun.com|g' /etc/apt/sources.list; \
        fi; \
        if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
            sed -i 's|http://deb.debian.org|https://mirrors.aliyun.com|g; s|http://security.debian.org|https://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources; \
        fi; \
    fi

# System packages required for building wheels (mysqlclient, sqlite, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential gcc git wget unzip \
        libsqlite3-dev default-libmysqlclient-dev pkg-config vim procps && \
    rm -rf /var/lib/apt/lists/*

# Use Aliyun PyPI mirror inside China. The mirror is served over HTTPS with a
# valid certificate, so no `trusted-host` opt-out is needed.
RUN set -eux; \
    if [ "${USE_CN_MIRROR}" = "true" ]; then \
        pip config set global.index-url https://mirrors.aliyun.com/pypi/simple; \
    fi

# Install datus-agent (fastembed + huggingface_hub come in transitively)
RUN pip install --no-cache-dir "datus-agent==${DATUS_VERSION}"

# Pin the fastembed cache path so the runtime resolves the same location the
# host prefetch wrote to. HF mirror env vars are retained as a fallback in
# case the runtime ever needs to fetch additional assets.
ENV HF_ENDPOINT=${HF_MIRROR_ENDPOINT} \
    HF_HUB_ENABLE_HF_TRANSFER=0 \
    HF_HUB_DOWNLOAD_TIMEOUT=120 \
    FASTEMBED_CACHE_PATH=/root/.cache/huggingface/fastembed

# Inject the fastembed model cache prefetched on the host
# (build_scripts/prefetch_model.sh writes here). docker_build.sh invokes the
# prefetch automatically when the directory is missing.
COPY build_scripts/cache/fastembed/ /root/.cache/huggingface/fastembed/

# Seed the default agent configuration at the runtime-expected location
RUN mkdir -p /root/.datus/conf
COPY conf/agent.yml.example /root/.datus/conf/agent.yml

WORKDIR /app

# Keep the container running
CMD ["tail", "-f", "/dev/null"]
