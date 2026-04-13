#!/bin/bash
#SBATCH --job-name=llm-test
#SBATCH --partition=poti
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:10:00
#SBATCH --output=llm_%j.out
#SBATCH --error=llm_%j.err

cd $HOME/comp-sys-perf-analysis

echo "Starting LLM benchmark..."

nix develop .#pcad --command python3 llm_test.py