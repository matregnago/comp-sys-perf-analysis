#!/bin/bash -l
#SBATCH --job-name=infer_vllm_tupi
#SBATCH --partition=tupi
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-task=1
#SBATCH --time=01:30:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -euo pipefail

echo "==============================================================="
echo "Date        : $(date)"
echo "SubmitHost  : $(hostname)"
echo "SubmitDir   : $SLURM_SUBMIT_DIR"
echo "JobID       : $SLURM_JOB_ID"
echo "Node(s)     : $SLURM_JOB_NODELIST"
echo "==============================================================="

if [ -f "$SLURM_SUBMIT_DIR/.env" ]; then
    set -a
    . "$SLURM_SUBMIT_DIR/.env"
    set +a
fi
: "${HF_TOKEN:?HF_TOKEN precisa estar em $SLURM_SUBMIT_DIR/.env}"

export MODEL="${MODEL:-meta-llama/Meta-Llama-3.1-8B-Instruct}"
export MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"
export GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.85}"
export CONCURRENCY_LIST="${CONCURRENCY_LIST:-1 4 8}"
export NSYS="${NSYS:-0}"

export RESULTS_DIR="$SLURM_SUBMIT_DIR/results_pcad/${SLURM_JOB_NAME}_${SLURM_JOB_ID}"
mkdir -p "$RESULTS_DIR"

srun --export=ALL bash <<'EOF'
set -euo pipefail
echo "--- Setup em $(hostname) ---"

WORK_DIR="$SCRATCH/cmp223"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

rm -rf scripts pyproject.toml flake.nix flake.lock uv.lock
cp -r "$SLURM_SUBMIT_DIR/scripts" .
cp "$SLURM_SUBMIT_DIR/pyproject.toml" .
cp "$SLURM_SUBMIT_DIR/flake.nix" .
cp "$SLURM_SUBMIT_DIR/flake.lock" .
cp "$SLURM_SUBMIT_DIR/uv.lock" .

export HF_HOME="$SCRATCH/hf_cache"
mkdir -p "$HF_HOME"

nix develop .#pcad --command bash -c '
set -euo pipefail
uv sync
export VENV_PATH="$PWD/.venv"
bash scripts/run_vllm_bench.sh
'
EOF

echo "=== Done. Artefatos em: $RESULTS_DIR ==="
