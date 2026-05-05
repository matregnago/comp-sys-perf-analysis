#!/bin/bash -l
#SBATCH --time=03:00:00
#SBATCH --output=./data/%x_%j/%j.out
#SBATCH --error=./data/%x_%j/%j.err

set -euxo pipefail

. "$SLURM_SUBMIT_DIR/scripts/config.sh"

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

mkdir -p "$FINAL_RESULTS_DIR"

nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
nodes_array=($nodes)

head_node=${nodes_array[0]}
export HEAD_NODE="${nodes_array[0]}"

head_ip=$(srun -N1 -n1 -w "$head_node" bash "$SLURM_SUBMIT_DIR/scripts/get_head_ip.sh")
export HEAD_IP="$head_ip"

port=6379
ip_head=$head_ip:$port
export ip_head

export BARRIER_DIR="$HOME/.ray_barriers/${SLURM_JOB_ID}"
rm -rf "$BARRIER_DIR"
mkdir -p "$BARRIER_DIR"
trap 'rm -rf "$BARRIER_DIR"' EXIT

srun --export=ALL \
    --nodes="$SLURM_JOB_NUM_NODES" \
    --ntasks="$SLURM_JOB_NUM_NODES" \
    --ntasks-per-node=1 \
    bash "$SLURM_SUBMIT_DIR/scripts/slurm_task_ray.sh"

echo "Job finalizado. Resultados (por hostname) em: $FINAL_RESULTS_DIR"
