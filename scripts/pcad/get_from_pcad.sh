#!/bin/bash

# Esse script eh mais um helper pra ajudar a passar as mudanças locais pro pcad
# Assim, nao precisa ficar commitando toda hora pra passar as alteracoes pra la

set -euo pipefail

[[ -f flake.nix ]] || { echo "rode a partir da raiz do projeto"; exit 1; }

SSH_HOST="pcad"
REMOTE_DIR="cmp223"

rsync --verbose --progress --recursive --links --times \
    --exclude='.git/' \
    --exclude='.claude/' \
    --exclude='.venv/' \
    --exclude='.direnv/' \
    --exclude='.ipynb_checkpoints/' \
    --exclude='__pycache__/' \
    --exclude='results_local/' \
    "${SSH_HOST}:~/${REMOTE_DIR}/" ./

echo "Dados movidos com sucesso!"
