#!/bin/bash -l
#SBATCH --job-name=infer_vllm
#SBATCH --partition=tupi
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-task=1
#SBATCH --time=03:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -euxo pipefail

# Variaveis configuraveis
. "$SLURM_SUBMIT_DIR/scripts/config.sh"

echo "==============================================================="
echo "Date        : $(date)"
echo "SubmitHost  : $(hostname)"
echo "SubmitDir   : $SLURM_SUBMIT_DIR"
echo "JobID       : $SLURM_JOB_ID"
echo "Node(s)     : $SLURM_JOB_NODELIST"
echo "==============================================================="


# Passa todas as variaveis do .env pro ambiente do pcad
# Necessaria pra deixar visivel o token do HF pro nodo de execucao
if [ -f "$SLURM_SUBMIT_DIR/.env" ]; then
    set -a
    . "$SLURM_SUBMIT_DIR/.env"
    set +a
fi
: "${HF_TOKEN:?HF_TOKEN precisa estar em $SLURM_SUBMIT_DIR/.env}"

mkdir -p "$FINAL_RESULTS_DIR"

srun --export=ALL bash "$SLURM_SUBMIT_DIR/scripts/slurm_task.sh"

echo "Job Finalizado. Arquivos salvos em: $FINAL_RESULTS_DIR"
