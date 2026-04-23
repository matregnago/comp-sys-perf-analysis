#!/bin/bash
#SBATCH --job-name=llm-test
#SBATCH --partition=beagle
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:30:00
#SBATCH --output=logs/llm_%j.out
#SBATCH --error=logs/llm_%j.err

# garantir que nixw está acessível
export PATH=$HOME/bin:/usr/bin:/bin:$PATH

# (opcional)
export NP_GIT=$(which git)

cd $HOME/comp-sys-perf-analysis

echo "Starting job on $(hostname)"

nixw nix develop .#pcad --command python3 llm_test/llm_test.py
