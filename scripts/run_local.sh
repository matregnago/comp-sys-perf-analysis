#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

export MODEL="${MODEL:-Qwen/Qwen2.5-1.5B-Instruct}"
export MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"
export GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.85}"
export RESULTS_DIR="${RESULTS_DIR:-$PROJECT_ROOT/results_local/$(date +%Y%m%d_%H%M%S)}"
export VENV_PATH="${VENV_PATH:-$PROJECT_ROOT/.venv}"

echo "=== Local run ==="
echo "    MODEL        = $MODEL"
echo "    RESULTS_DIR  = $RESULTS_DIR"
echo "    VENV_PATH    = $VENV_PATH"
echo "    NSYS         = ${NSYS:-0}"

bash "$PROJECT_ROOT/scripts/run_vllm_bench.sh"
