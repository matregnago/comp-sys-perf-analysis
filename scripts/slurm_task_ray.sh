#!/bin/bash
set -euxo pipefail

NODE_HOST="$(hostname)"
echo "[$NODE_HOST] iniciando setup do nodo"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Limpa scripts/lock files de execucoes anteriores
rm -rf scripts pyproject.toml flake.nix flake.lock uv.lock

cp -r "$SLURM_SUBMIT_DIR/scripts" .
cp "$SLURM_SUBMIT_DIR/pyproject.toml" .
cp "$SLURM_SUBMIT_DIR/flake.nix" .
cp "$SLURM_SUBMIT_DIR/flake.lock" .
cp "$SLURM_SUBMIT_DIR/uv.lock" .

mkdir -p "$HF_HOME"

export NODE_RESULTS_DIR="$RESULTS_DIR/$NODE_HOST"
export NODE_FINAL_RESULTS_DIR="$FINAL_RESULTS_DIR/$NODE_HOST"
mkdir -p "$NODE_RESULTS_DIR" "$NODE_FINAL_RESULTS_DIR"

copyback() {
    echo "[$NODE_HOST] copiando $NODE_RESULTS_DIR -> $NODE_FINAL_RESULTS_DIR"
    if [ -d "$NODE_RESULTS_DIR" ]; then
        cp -r "$NODE_RESULTS_DIR/." "$NODE_FINAL_RESULTS_DIR/" || true
    fi
}
trap copyback EXIT

nixw nix run .#default -- -c '
set -euxo pipefail

uv sync --extra pcad
source .venv/bin/activate

export VENV_PATH="$PWD/.venv"
export VIRTUAL_ENV="$PWD/.venv"

# Barreira: sinaliza que este nodo terminou o uv sync e aguarda os demais
# antes de subir o ray symmetric-run. BARRIER_DIR e exportado pelo .slurm.
: "${BARRIER_DIR:?BARRIER_DIR obrigatorio (exportado pelo infer_ray.slurm)}"
node_host="$(hostname)"
mkdir -p "$BARRIER_DIR"
touch "$BARRIER_DIR/${node_host}.ready"
echo "[$node_host] aguardando barreira ($SLURM_JOB_NUM_NODES nodos) em $BARRIER_DIR"
{ set +x; } 2>/dev/null
while [ "$(find "$BARRIER_DIR" -maxdepth 1 -name "*.ready" -type f 2>/dev/null | wc -l)" -lt "$SLURM_JOB_NUM_NODES" ]; do
    sleep 2
done
set -x
echo "[$node_host] barreira liberada"

bash scripts/ray_node_run.sh
' >"$NODE_RESULTS_DIR/node.log" 2>&1
