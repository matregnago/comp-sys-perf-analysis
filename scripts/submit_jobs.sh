#!/bin/bash

set -euo pipefail

[[ -f flake.nix ]] || { echo "rode da raiz do projeto"; exit 1; }

CSV_FILE="${CSV_FILE:-projeto_experimental.csv}"
SLURM_SCRIPT="${SLURM_SCRIPT:-slurm/infer_ray.slurm}"

[[ -f "$CSV_FILE" ]]     || { echo "CSV nao encontrado: $CSV_FILE"; exit 1; }
[[ -f "$SLURM_SCRIPT" ]] || { echo "slurm script nao encontrado: $SLURM_SCRIPT"; exit 1; }

mkdir -p data

# Pula header e ignora linhas em branco / coments.
tail -n +2 "$CSV_FILE" | while IFS=',' read -r order n_gpus no_pcad nodes gpus_per_node tp pp isl osl; do
    [[ -z "${order// }" ]] && continue
    [[ "${order:0:1}" == "#" ]] && continue

    echo "[submit] $order  partition=$no_pcad nodes=$nodes gpus_per_node=$gpus_per_node tp=$tp pp=$pp isl=$isl osl=$osl"

    sbatch \
        --job-name="$order" \
        --partition="$no_pcad" \
        --nodes="$nodes" \
        --gpus-per-node="$gpus_per_node" \
        --export="ALL,TP_SIZE=$tp,PP_SIZE=$pp,ISL=$isl,OSL=$osl" \
        "$SLURM_SCRIPT"
done

echo "[submit] todos os jobs submetidos"
