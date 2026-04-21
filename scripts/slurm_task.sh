#!/bin/bash
set -euo pipefail

echo "Iniciando setup em $(hostname)"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Remove os scripts da execucao anterior (talvez seria mais interessante apagar o scratch inteiro logo, mas podemos decidir depois)
rm -rf scripts pyproject.toml flake.nix flake.lock uv.lock

# Copia os scripts e arquivos necessarios para rodar o projeto para o workdit no scratch do nodo
cp -r "$SLURM_SUBMIT_DIR/scripts" .
cp "$SLURM_SUBMIT_DIR/pyproject.toml" .
cp "$SLURM_SUBMIT_DIR/flake.nix" .
cp "$SLURM_SUBMIT_DIR/flake.lock" .
cp "$SLURM_SUBMIT_DIR/uv.lock" .

# Cache pra nao baixar o modelo toda hora
mkdir -p "$HF_HOME"

mkdir -p "$RESULTS_DIR"

# Funcao pra copiar os dados do scratch de volta pra home
copyback() {
    echo "Copiando resultados do SCRATCH para HOME: $RESULTS_DIR -> $FINAL_RESULTS_DIR"
    if [ -d "$RESULTS_DIR" ]; then
        cp -r "$RESULTS_DIR/." "$FINAL_RESULTS_DIR/" || true
    fi
}
# Copia os dados de volta para a home caso o job finalize ou ocorra algum erro
trap copyback EXIT

# Executa o flake do nix
nixw nix develop .#pcad --command bash -c '
set -euo pipefail

# Instala os pacotes do uv
uv sync

export VENV_PATH="$PWD/.venv"
bash scripts/run_vllm_bench.sh
'
