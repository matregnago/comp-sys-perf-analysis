#!/bin/bash -l
#SBATCH --job-name=infer_ray
#SBATCH --partition=poti
#SBATCH --nodes=1
#SBATCH --nodelist=poti5
#SBATCH --ntasks-per-node=1
#SBATCH --time=03:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

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

# Resolve o IP 192.168.* do head via srun. O symmetric-run do Ray compara IP
# local com o do --address pra decidir head/worker; passar hostname falha
# porque gethostbyname pode retornar um IP diferente do da interface.
head_ip=$(srun -N1 -n1 -w "$head_node" bash "$SLURM_SUBMIT_DIR/scripts/get_head_ip.sh")
export HEAD_IP="$head_ip"

# Porta derivada do JOB_ID para evitar conflito com Redis (6379) ou
# instancias de Ray deixadas por jobs anteriores no mesmo nodo.
port=6379
ip_head=$head_ip:$port
export ip_head

# Barreira inter-nodos via arquivos em diretorio compartilhado ($HOME e NFS
# no PCAD). Cada nodo, depois do uv sync, escreve <hostname>.ready aqui e
# espera ate ver SLURM_JOB_NUM_NODES arquivos antes de subir o ray.
# Sem isso o ray symmetric-run pode iniciar enquanto outro nodo ainda esta
# baixando pacotes.
export BARRIER_DIR="$HOME/.ray_barriers/${SLURM_JOB_ID}"
rm -rf "$BARRIER_DIR"
mkdir -p "$BARRIER_DIR"
trap 'rm -rf "$BARRIER_DIR"' EXIT

# Um srun por nodo. Cada nodo executa o setup do scratch + nix develop + ray symmetric-run.
# O entrypoint de bench roda APENAS no head (controlado pelo ray symmetric-run).
srun --export=ALL \
    --nodes="$SLURM_JOB_NUM_NODES" \
    --ntasks="$SLURM_JOB_NUM_NODES" \
    --ntasks-per-node=1 \
    bash "$SLURM_SUBMIT_DIR/scripts/slurm_task_ray.sh"

echo "Job finalizado. Resultados (por hostname) em: $FINAL_RESULTS_DIR"
