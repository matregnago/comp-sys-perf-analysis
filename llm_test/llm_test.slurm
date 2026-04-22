#!/bin/bash
#SBATCH --job-name=llm-test
#SBATCH --partition=poti
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:30:00
#SBATCH --output=llm_%j.out
#SBATCH --error=llm_%j.err

PROJECT_DIR=$HOME/comp-sys-perf-analysis/comp-sys-perf-analysis

echo "Starting LLM benchmark..."

cd $PROJECT_DIR

nix develop .#pcad --command python3 llm_test/llm_test.py