#!/bin/bash
#SBATCH --job-name=test-cuda
#SBATCH --partition=poti
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:10:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

cd $HOME/comp-sys-perf-analysis

nix develop .#pcad --command python3 test_cuda.py
