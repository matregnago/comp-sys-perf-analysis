#!/bin/bash
set -euo pipefail

[[ -f flake.nix ]] || { echo "rode da raiz do projeto"; exit 1; }

CSV_FILE="projeto_experimental.csv"
SLURM_SCRIPT="slurm/benchmark.slurm"

[[ -f "$CSV_FILE" ]]     || { echo "CSV nao encontrado: $CSV_FILE"; exit 1; }
[[ -f "$SLURM_SCRIPT" ]] || { echo "slurm script nao encontrado: $SLURM_SCRIPT"; exit 1; }

mkdir -p data

# Pula header
tail -n +2 "$CSV_FILE" | while IFS=',' read -r order n_gpus no_pcad nodes gpus_per_node tp pp isl osl exp_type; do
    [[ -z "${order// }" ]] && continue
    [[ "${order:0:1}" == "#" ]] && continue

    case "$exp_type" in
        trace)
            export NSYS=1
            export CONCURRENCY_LEVELS=""
            sbatch_time="$SBATCH_TIME_TRACE"
            ;;
        concurrency)
            export NSYS=0
            export CONCURRENCY_LEVELS="$CONCURRENCY_LEVELS"
            export REQUESTS_PER_CONCURRENCY="$REQUESTS_PER_CONCURRENCY"
            export MAX_REQUESTS="$MAX_REQUESTS"
            sbatch_time="$SBATCH_TIME_CONC"
            ;;
        *)
            continue
            ;;
    esac

    echo "[submit] $order  type=$exp_type partition=$no_pcad nodes=$nodes gpus_per_node=$gpus_per_node tp=$tp pp=$pp isl=$isl osl=$osl nsys=$NSYS conc=[$CONCURRENCY_LEVELS] time=$sbatch_time"

    sbatch \
        --job-name="$order" \
        --partition="$no_pcad" \
        --nodes="$nodes" \
        --gpus-per-node="$gpus_per_node" \
        --time="$sbatch_time" \
        --export="ALL,TP_SIZE=$tp,PP_SIZE=$pp,ISL=$isl,OSL=$osl" \
        "$SLURM_SCRIPT"
done
