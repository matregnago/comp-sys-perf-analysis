#!/bin/bash
set -euo pipefail

: "${RESULTS_DIR:?RESULTS_DIR obrigatório}"
: "${VENV_PATH:?VENV_PATH obrigatório}"

MODEL="${MODEL:-meta-llama/Meta-Llama-3.1-8B-Instruct}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.85}"
PORT="${PORT:-8000}"
ISL="${ISL:-128}"
OSL="${OSL:-128}"
REQUEST_COUNT="${REQUEST_COUNT:-30}"
CONCURRENCY_LIST="${CONCURRENCY_LIST:-1 4 8}"

mkdir -p "$RESULTS_DIR"
source "$VENV_PATH/bin/activate"

# Telemetria nvidia-smi
TELEMETRY_CSV="$RESULTS_DIR/telemetry.csv"
nvidia-smi \
    --query-gpu=timestamp,index,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu,clocks.current.sm,clocks.current.memory \
    --format=csv,nounits \
    --loop-ms=100 > "$TELEMETRY_CSV" &
NVSMI_PID=$!
echo "=== nvidia-smi PID=$NVSMI_PID -> $TELEMETRY_CSV ==="

cleanup() {
    echo "=== Cleanup: SIGINT em vLLM (pra nsys finalizar) + kill nvidia-smi ==="
    [ -n "${VLLM_PID:-}" ] && kill -INT $VLLM_PID 2>/dev/null || true
    [ -n "${NVSMI_PID:-}" ] && kill $NVSMI_PID 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT

VLLM_LOG="$RESULTS_DIR/vllm_server.log"
VLLM_ARGS=(
    "$MODEL"
    --max-model-len "$MAX_MODEL_LEN"
    --gpu-memory-utilization "$GPU_MEM_UTIL"
    --port "$PORT"
    --host 127.0.0.1
)

if [ "${NSYS:-0}" = "1" ]; then
    NSYS_OUT="$RESULTS_DIR/vllm_trace"
    echo "=== NSYS=1: envolvendo vLLM com nsys -> ${NSYS_OUT}.nsys-rep ==="
    nsys profile \
        --output="$NSYS_OUT" \
        --force-overwrite=true \
        --trace=cuda,nvtx,cudnn,cublas,nccl \
        --sample=none \
        vllm serve "${VLLM_ARGS[@]}" > "$VLLM_LOG" 2>&1 &
else
    vllm serve "${VLLM_ARGS[@]}" > "$VLLM_LOG" 2>&1 &
fi
VLLM_PID=$!
echo "=== vLLM PID=$VLLM_PID, model=$MODEL, log=$VLLM_LOG ==="

# Health poll (timeout 10 min)
echo "=== Aguardando vLLM ficar pronto ==="
for i in $(seq 1 120); do
    if curl -sf "http://127.0.0.1:$PORT/v1/models" > /dev/null 2>&1; then
        echo "=== vLLM pronto apos ${i}x5s ==="
        break
    fi
    if ! kill -0 $VLLM_PID 2>/dev/null; then
        echo "ERRO: vLLM morreu durante startup. Ultimas linhas:"
        tail -50 "$VLLM_LOG"
        exit 1
    fi
    sleep 5
done

if ! curl -sf "http://127.0.0.1:$PORT/v1/models" > /dev/null 2>&1; then
    echo "ERRO: vLLM nao ficou pronto em 10 min"
    tail -80 "$VLLM_LOG"
    exit 1
fi

# Matriz aiperf
for c in $CONCURRENCY_LIST; do
    echo "=== aiperf concurrency=$c ==="
    aiperf profile \
        --model "$MODEL" \
        --endpoint-type chat \
        --url "http://127.0.0.1:$PORT" \
        --streaming \
        --concurrency "$c" \
        --request-count "$REQUEST_COUNT" \
        --warmup-request-count 3 \
        --prompt-input-tokens-mean "$ISL" \
        --prompt-output-tokens-mean "$OSL" \
        --extra-inputs ignore_eos:true \
        --output-artifact-dir "$RESULTS_DIR/c${c}"
done

echo "=== Concluido. Artefatos em: $RESULTS_DIR ==="
