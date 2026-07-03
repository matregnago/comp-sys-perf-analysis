#!/bin/bash

# configs gerais
export WORK_DIR="$SCRATCH/cmp223"
export HF_HOME="$SCRATCH/hf_cache"
export FINAL_RESULTS_DIR="$SLURM_SUBMIT_DIR/data/${SLURM_JOB_NAME}_${SLURM_JOB_ID}"
export RESULTS_DIR="$WORK_DIR/results/${SLURM_JOB_NAME}_${SLURM_JOB_ID}"


# vLLM
MODEL="Qwen/Qwen2.5-7B-Instruct" # Modelo que o vLLM vai carregar
MAX_MODEL_LEN="4096" # Comprimento maximo de contexto (ISL + OSL)
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.85}"
HOST="127.0.0.1" # Host do servidor vLLM
PORT="8000" # Porta do servidor vLLM
HEALTH_POLL_TRIES="120" # Numero de tentativas ate o vLLM responder no /v1/models
HEALTH_POLL_SLEEP="5"   # Segundos entre tentativas (timeout total = tries * sleep)
export VLLM_CACHE_ROOT="$WORK_DIR/.vllm_cache"
export VLLM_CONFIG_ROOT="$WORK_DIR/.vllm_config"

# aiperf
ISL="${ISL:-128}" # Tamanho do prompt de entrada em tokens   (sobrescrito por job)
OSL="${OSL:-128}" # Tamanho da resposta (saida) em tokens    (sobrescrito por job)
REQUEST_COUNT="30" # Requests por medicao (piso; vira teto inferior na varredura)
WARMUP_COUNT="3" # Requests de warmup antes da medicao (piso na varredura)
MAX_REQUESTS="${MAX_REQUESTS:-640}"
CONCURRENCY_LEVELS="1 2 4 8 16 32"
REQUESTS_PER_CONCURRENCY="10"

# telemetria
NSYS="${NSYS:-1}"
NVSMI_INTERVAL_MS="100"

# iperf3
IPERF=1
IPERF_PORT=5201
IPERF_DURATION=10
IPERF_PARALLEL=4
