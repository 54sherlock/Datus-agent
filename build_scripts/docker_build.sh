#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$SCRIPT_DIR/cache/fastembed"

USE_CN_MIRROR="${USE_CN_MIRROR:-true}"

if [[ -z "${DATUS_VERSION:-}" ]]; then
    if command -v python3 >/dev/null 2>&1; then
        DATUS_VERSION="$(python3 - "$PROJECT_ROOT/pyproject.toml" <<'PY'
import sys
import tomllib
from pathlib import Path

pyproject = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(pyproject["project"]["version"])
PY
        )"
    else
        DATUS_VERSION="0.3.3"
    fi
fi

if [[ "${USE_CN_MIRROR}" == "true" ]]; then
    BASE_IMAGE="${BASE_IMAGE:-m.daocloud.io/docker.io/library/python:3.12-slim}"
    HF_MIRROR_ENDPOINT="${HF_MIRROR_ENDPOINT:-https://hf-mirror.com}"
else
    BASE_IMAGE="${BASE_IMAGE:-python:3.12-slim}"
    HF_MIRROR_ENDPOINT="${HF_MIRROR_ENDPOINT:-https://huggingface.co}"
fi

# Ensure the fastembed model cache is populated on the host before building;
# the Dockerfile COPY-step pulls from this directory.
if ! HF_ENDPOINT="${HF_MIRROR_ENDPOINT}" "$SCRIPT_DIR/prefetch_model.sh" --check-only; then
    echo "[build] fastembed cache missing or incomplete, running prefetch..."
    HF_ENDPOINT="${HF_MIRROR_ENDPOINT}" "$SCRIPT_DIR/prefetch_model.sh"
fi

docker build \
    --build-arg "DATUS_VERSION=${DATUS_VERSION}" \
    --build-arg "USE_CN_MIRROR=${USE_CN_MIRROR}" \
    --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
    --build-arg "HF_MIRROR_ENDPOINT=${HF_MIRROR_ENDPOINT}" \
    -t datus-agent:latest \
    -f "$SCRIPT_DIR/Dockerfile" \
    "$PROJECT_ROOT"
