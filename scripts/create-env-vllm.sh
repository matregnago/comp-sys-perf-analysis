#!/usr/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v uv >/dev/null 2>&1; then
    echo "uv nao encontrado"
    exit 1
fi

uv --version

cd "$PROJECT_ROOT"
uv sync

echo "venv pronto"
uv run python -c "import torch, vllm; print('torch', torch.__version__, 'CUDA', torch.cuda.is_available()); print('vllm', vllm.__version__)"
uv run aiperf --version
