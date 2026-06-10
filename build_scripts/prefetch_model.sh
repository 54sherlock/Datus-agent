#!/usr/bin/env bash
# Pre-download fastembed's all-MiniLM-L6-v2 model on the host into a local
# cache directory so the Docker build can COPY it into the image. Use this
# when the Docker build network can't reach huggingface.co / hf-mirror.com
# directly.
#
# Override the HF endpoint via the environment if needed:
#   HF_ENDPOINT=https://huggingface.co ./build_scripts/prefetch_model.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$SCRIPT_DIR/cache/fastembed"
CHECK_ONLY=false

if [[ "${1:-}" == "--check-only" ]]; then
    CHECK_ONLY=true
fi

export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-0}"
export FASTEMBED_CACHE_PATH="$CACHE_DIR"

mkdir -p "$CACHE_DIR"

if command -v uv >/dev/null 2>&1 && [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
    RUNNER=(uv run --project "$PROJECT_ROOT" python -)
else
    RUNNER=(python3 -)
fi

validate_or_populate_cache() {
    "${RUNNER[@]}" <<'PY'
import os
import sys
from pathlib import Path

from fastembed import TextEmbedding
from huggingface_hub import snapshot_download
from huggingface_hub.errors import LocalEntryNotFoundError

cache_dir = Path(os.environ["FASTEMBED_CACHE_PATH"])
model_name = "sentence-transformers/all-MiniLM-L6-v2"
required_files = ("model.onnx", "config.json", "tokenizer.json", "tokenizer_config.json")
optional_files = ("special_tokens_map.json", "vocab.txt")


def resolve_repo_id() -> str:
    description = TextEmbedding._get_model_description(model_name)
    if isinstance(description, dict):
        return description.get("sources", {}).get("hf")
    return description.sources.hf


def snapshot_path_if_complete() -> Path | None:
    repo_id = resolve_repo_id()
    try:
        snap_path = Path(snapshot_download(repo_id, cache_dir=str(cache_dir), local_files_only=True))
    except LocalEntryNotFoundError:
        return None
    missing = [name for name in required_files if not (snap_path / name).is_file()]
    if missing:
        print(f"[prefetch] HF snapshot incomplete at {snap_path}, missing: {missing}", file=sys.stderr)
        return None
    return snap_path


def populate_snapshot_from_native() -> Path:
    repo_id = resolve_repo_id()
    native_dir = cache_dir / "fast-all-MiniLM-L6-v2"
    hf_dir = cache_dir / f"models--{repo_id.replace('/', '--')}"
    ref_file = hf_dir / "refs" / "main"

    if not ref_file.is_file():
        raise FileNotFoundError(f"expected ref file {ref_file} not found")
    if not native_dir.is_dir():
        raise FileNotFoundError(f"native cache {native_dir} not found")

    commit = ref_file.read_text(encoding="utf-8").strip()
    if not commit:
        raise ValueError(f"empty commit hash in {ref_file}")

    snap_dir = hf_dir / "snapshots" / commit
    snap_dir.mkdir(parents=True, exist_ok=True)

    for filename in required_files:
        source = native_dir / filename
        if not source.is_file():
            raise FileNotFoundError(f"required artifact missing: {source}")
        target = snap_dir / filename
        target.write_bytes(source.read_bytes())

    for filename in optional_files:
        source = native_dir / filename
        if source.is_file():
            target = snap_dir / filename
            target.write_bytes(source.read_bytes())

    return snap_dir


check_only = os.environ.get("PREFETCH_CHECK_ONLY") == "1"
snap_path = snapshot_path_if_complete()
if snap_path is not None:
    print(f"[prefetch] HF snapshot ready: {snap_path}")
    raise SystemExit(0)

if check_only:
    raise SystemExit(1)

native_dir = cache_dir / "fast-all-MiniLM-L6-v2"
if native_dir.is_dir():
    snap_path = populate_snapshot_from_native()
    print(f"[prefetch] snapshot populated from native cache: {snap_path}")
    raise SystemExit(0)

print("[prefetch] ERROR: cache layout not recognized after download.", file=sys.stderr)
print(f"[prefetch] cache_dir={cache_dir}", file=sys.stderr)
for path in sorted(cache_dir.rglob("*")):
    if path.is_file():
        print(f"[prefetch]   file: {path.relative_to(cache_dir)}", file=sys.stderr)
raise SystemExit(1)
PY
}

if [[ "$CHECK_ONLY" == "true" ]]; then
    export PREFETCH_CHECK_ONLY=1
    validate_or_populate_cache
    exit $?
fi

echo "[prefetch] HF_ENDPOINT=$HF_ENDPOINT"
echo "[prefetch] cache_dir=$CACHE_DIR"

# Step 1: download the model via fastembed. When HF is reachable this populates
# the huggingface_hub snapshot layout directly. When HF is unreachable fastembed
# falls back to its native mirror under fast-all-MiniLM-L6-v2/.
"${RUNNER[@]}" <<'PY'
import os
from fastembed import TextEmbedding

cache_dir = os.environ["FASTEMBED_CACHE_PATH"]
model = TextEmbedding(model_name="sentence-transformers/all-MiniLM-L6-v2", cache_dir=cache_dir)
list(model.embed(["warmup"]))
print("[prefetch] fastembed download done")
PY

# Step 2: verify the HF snapshot datus expects, or mirror native files into it.
unset PREFETCH_CHECK_ONLY
validate_or_populate_cache

# Strip macOS AppleDouble sidecar files that confuse Linux readers.
find "$CACHE_DIR" -name '._*' -delete 2>/dev/null || true

echo "[prefetch] model cached at $CACHE_DIR"
