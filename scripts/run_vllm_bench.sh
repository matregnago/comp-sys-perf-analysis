#!/bin/bash
set -euo pipefail

[[ -f flake.nix ]] || { echo "rode da raiz do projeto"; exit 1; }

# Import das configuracoes
. scripts/config.sh

: "${RESULTS_DIR:?RESULTS_DIR obrigatório}"
: "${VENV_PATH:?VENV_PATH obrigatório}"

mkdir -p "$RESULTS_DIR"

# Diretorio necessario. Da erro se tirar
mkdir -p "$RESULTS_DIR/.mplcache"

# Inicia a telemetria com o nvidia-smi
nvidia-smi \
    --query-gpu=timestamp,index,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu,clocks.current.sm,clocks.current.memory \
    --format=csv,nounits \
    --loop-ms="$NVSMI_INTERVAL_MS" > "$TELEMETRY_CSV" &
NVSMI_PID=$!

echo "Configuracoes carregadas do nvidia-smi:"
echo "nvidia-smi PID -> $NVSMI_PID"
echo "Arquivo de saida -> $TELEMETRY_CSV"

# Mata os processos do vLLM e nvidia-smi
cleanup() {
    echo "Executando cleanup no nvidia-smi e no vLLM"
    [ -n "${VLLM_PID:-}" ] && kill -INT $VLLM_PID 2>/dev/null || true
    [ -n "${NVSMI_PID:-}" ] && kill $NVSMI_PID 2>/dev/null || true
    wait 2>/dev/null || true
}
# Mata os processos caso o job finalize ou ocorra algum erro
trap cleanup EXIT

VLLM_ARGS=(
    "$MODEL"
    --max-model-len "$MAX_MODEL_LEN"
    --gpu-memory-utilization "$GPU_MEM_UTIL"
    --host "$HOST"
    --port "$PORT"
)

# Onicializa o vLLM e o nsys (caso a flag NSYS esteja habilitada)
if [ "${NSYS:-0}" = "1" ]; then
    echo "Habilitando nsys para o vLLM"
    nsys profile \
        --output="$NSYS_OUT" \
        --force-overwrite=true \
        --trace=cuda,nvtx,cudnn,cublas,nccl \
        --sample=none \
        uv run --no-sync vllm serve "${VLLM_ARGS[@]}" > "$VLLM_LOG" 2>&1 &
else
    uv run --no-sync vllm serve "${VLLM_ARGS[@]}" > "$VLLM_LOG" 2>&1 &
fi
VLLM_PID=$!

echo "Configuracoes carregadas do vLLM:"
echo "vLLM PID -> $VLLM_PID"
echo "model -> $MODEL"
echo "log -> $VLLM_LOG"

# Espera e verifica periodicamente a inicializacao do servidor do vLLM
echo "Aguardando vLLM ficar pronto..."
for i in $(seq 1 "$HEALTH_POLL_TRIES"); do
    if curl -sf "http://$HOST:$PORT/v1/models" > /dev/null 2>&1; then
        echo "vLLM pronto apos ${i}x${HEALTH_POLL_SLEEP}s"
        break
    fi
    if ! kill -0 $VLLM_PID 2>/dev/null; then
        echo "ERRO: vLLM morreu durante startup. Ultimas linhas:"
        tail -50 "$VLLM_LOG"
        exit 1
    fi
    sleep "$HEALTH_POLL_SLEEP"
done

# Timeout caso o servidor do vLLM nao fique pronto ate o tempo limite
if ! curl -sf "http://$HOST:$PORT/v1/models" > /dev/null 2>&1; then
    echo "ERRO: vLLM nao ficou pronto no tempo limite"
    tail -80 "$VLLM_LOG"
    exit 1
fi

# Inicializacao do benchmark do aiperf
uv run --no-sync aiperf profile \
    --model "$MODEL" \
    --endpoint-type chat \
    --url "http://$HOST:$PORT" \
    --streaming \
    --request-count "$REQUEST_COUNT" \
    --warmup-request-count "$WARMUP_COUNT" \
    --prompt-input-tokens-mean "$ISL" \
    --prompt-output-tokens-mean "$OSL" \
    --extra-inputs ignore_eos:true \
    --output-artifact-dir "$RESULTS_DIR"

echo "Execução do benchmark concluida!"
