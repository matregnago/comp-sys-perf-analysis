#!/bin/bash

# Paths
export SCRATCH="/scratch/matregnago"
export WORK_DIR="$SCRATCH/cmp223"
export HF_HOME="$SCRATCH/hf_cache"
export FINAL_RESULTS_DIR="$SLURM_SUBMIT_DIR/data/${SLURM_JOB_NAME}_${SLURM_JOB_ID}"
export RESULTS_DIR="$WORK_DIR/results/${SLURM_JOB_NAME}_${SLURM_JOB_ID}"

# nsys
NSYS=0 # Ativar o trace do nsys

# Arquivos de saida
VLLM_LOG="$RESULTS_DIR/vllm_server.log" # Log do servidor vLLM
TELEMETRY_CSV="$RESULTS_DIR/telemetry.csv" # CSV do nvidia-smi
NSYS_OUT="$RESULTS_DIR/vllm_trace" # Trace do nsys (se NSYS=1)

# vLLM
MODEL="Qwen/Qwen2.5-7B-Instruct" # Modelo que o vLLM vai carregar
MAX_MODEL_LEN="4096" # Comprimento maximo de contexto (ISL + OSL)
GPU_MEM_UTIL="0.85" # Porcentagem da VRAM que o vLLM pode usar
HOST="127.0.0.1" # Host do servidor vLLM
PORT="8000" # Porta do servidor vLLM
HEALTH_POLL_TRIES="120" # Numero de tentativas para verificar quando o vLLM fica pronto
HEALTH_POLL_SLEEP="5"   # Segundos entre tentativas (total = tries * sleep)

# aiperf
ISL="128" # Tamanho do prompt de entrada em tokens
OSL="128" # Tamanho da resposta (saida) em tokens
REQUEST_COUNT="30" # Quantidade de requests enviados
WARMUP_COUNT="3" # Requests de warmup antes da medicao

# Telemetria
NVSMI_INTERVAL_MS="100" # Intervalo de amostragem do nvidia-smi em ms
