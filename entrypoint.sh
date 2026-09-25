#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="${MODEL_DIR:-/models}"
REPO="prism-ml/Ternary-Bonsai-2-27B-gguf"

# PQ2_0 (7.21 GB): faster prompt processing everywhere, faster decode on H100/A100/Blackwell.
# PTQ1_0 (5.95 GB): smaller, faster decode on Ada-gen GPUs / L4, best when memory is tight.
PACKING="${BONSAI_PACKING:-PQ2_0}"
FILENAME="Ternary-Bonsai-2-27B-${PACKING}.gguf"
MODEL_PATH="${MODEL_DIR}/${FILENAME}"

mkdir -p "$MODEL_DIR"

if [ ! -f "$MODEL_PATH" ]; then
    echo "[bonsai2] Downloading ${FILENAME} (cached in the volume after this)..."
    curl -fL --retry 3 -o "${MODEL_PATH}.part" \
        "https://huggingface.co/${REPO}/resolve/main/${FILENAME}"
    mv "${MODEL_PATH}.part" "$MODEL_PATH"
else
    echo "[bonsai2] Using cached model at ${MODEL_PATH}"
fi

# Optional vision projector (multimodal input). Only downloaded/loaded if enabled.
if [ "${BONSAI_VISION:-0}" = "1" ]; then
    MMPROJ="Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf"
    MMPROJ_PATH="${MODEL_DIR}/${MMPROJ}"
    if [ ! -f "$MMPROJ_PATH" ]; then
        echo "[bonsai2] Downloading vision projector ${MMPROJ}..."
        curl -fL --retry 3 -o "${MMPROJ_PATH}.part" \
            "https://huggingface.co/${REPO}/resolve/main/${MMPROJ}" || \
            echo "[bonsai2] WARNING: could not fetch mmproj file, continuing text-only"
        [ -f "${MMPROJ_PATH}.part" ] && mv "${MMPROJ_PATH}.part" "$MMPROJ_PATH"
    fi
    MMPROJ_ARGS=(--mmproj "$MMPROJ_PATH")
else
    MMPROJ_ARGS=()
fi

echo "[bonsai2] Starting llama-server on ${BONSAI_HOST:-0.0.0.0}:${PORT:-8080} (ctx=${BONSAI_CTX:-8192}, ngl=${BONSAI_NGL:-0})"

# shellcheck disable=SC2086
exec /opt/bonsai/bin/llama-server \
    -m "$MODEL_PATH" \
    "${MMPROJ_ARGS[@]}" \
    --host "${BONSAI_HOST:-0.0.0.0}" \
    --port "${PORT:-8080}" \
    -ngl "${BONSAI_NGL:-0}" \
    -c "${BONSAI_CTX:-8192}" \
    -fa on \
    --temp "${BONSAI_TEMP:-1.0}" \
    --top-p "${BONSAI_TOP_P:-0.95}" \
    --top-k "${BONSAI_TOP_K:-20}" \
    --min-p "${BONSAI_MIN_P:-0.05}" \
    ${BONSAI_EXTRA_ARGS:-}