#!/bin/bash
# Entrypoint do ray symmetric-run: roda APENAS no head.
# Sobe vLLM com backend Ray (usando o cluster ja inicializado pelos workers)
# e entao dispara o aiperf contra o servidor.
set -euo pipefail

[[ -f flake.nix ]] || { echo "rode da raiz do projeto"; exit 1; }

. scripts/config.sh

: "${RESULTS_DIR:?RESULTS_DIR obrigatorio}"
: "${VIRTUAL_ENV:?VIRTUAL_ENV obrigatorio (venv ativado pelo shellHook do flake)}"
: "${ip_head:?ip_head obrigatorio (IP:porta do head Ray, definido pelo infer_ray.slurm)}"

# Sem isso o ray.init() interno do vLLM faz bootstrap de um cluster novo
# em vez de conectar no que o symmetric-run ja subiu.
export RAY_ADDRESS="$ip_head"

# VLLM_HOST_IP deve ser definido por nodo no bootstrap do Ray (ray_node_run.sh).
# Aqui apenas garantimos fallback para o head caso nao venha setado.
if [ -z "${VLLM_HOST_IP:-}" ]; then
    HEAD_IP="${ip_head%%:*}"
    export VLLM_HOST_IP="$HEAD_IP"
fi

# Evita warning/performance hit do matplotlib quando $HOME nao e gravavel no nodo.
export MPLCONFIGDIR="${MPLCONFIGDIR:-$RESULTS_DIR/.mplcache}"

HEAD_HOST="$(hostname)"
HEAD_RESULTS="$RESULTS_DIR/$HEAD_HOST"
mkdir -p "$HEAD_RESULTS"
mkdir -p "$MPLCONFIGDIR"

VLLM_LOG="$HEAD_RESULTS/vllm_server.log"

# Topologia paralela: por padrao TP=GPUs/no, PP=numero de nodos.
TP_SIZE="${TP_SIZE:-${SLURM_GPUS_PER_TASK:-1}}"
PP_SIZE="${PP_SIZE:-${SLURM_JOB_NUM_NODES:-1}}"

VLLM_ARGS=(
    "$MODEL"
    --max-model-len "$MAX_MODEL_LEN"
    --gpu-memory-utilization "$GPU_MEM_UTIL"
    --host "$HOST"
    --port "$PORT"
    --distributed-executor-backend ray
    --tensor-parallel-size "$TP_SIZE"
    --pipeline-parallel-size "$PP_SIZE"
)

cleanup() {
    echo "[head] cleanup vLLM"
    [ -n "${VLLM_PID:-}" ] && kill -INT "$VLLM_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT

echo "[head] subindo vLLM com backend Ray (TP=$TP_SIZE, PP=$PP_SIZE)"
vllm serve "${VLLM_ARGS[@]}" > "$VLLM_LOG" 2>&1 &
VLLM_PID=$!

healthcheck() {
    python - "$HOST" "$PORT" <<'PY'
import json
import sys
import urllib.request

host, port = sys.argv[1], sys.argv[2]
url = f"http://{host}:{port}/v1/models"
with urllib.request.urlopen(url, timeout=2) as resp:
    if resp.status != 200:
        raise RuntimeError(f"status={resp.status}")
    json.loads(resp.read().decode("utf-8"))
print("ok")
PY
}

echo "[head] aguardando vLLM ficar pronto..."
for i in $(seq 1 "$HEALTH_POLL_TRIES"); do
    if healthcheck > /dev/null 2>&1; then
        echo "[head] vLLM pronto apos ${i}x${HEALTH_POLL_SLEEP}s"
        break
    fi
    if ! kill -0 "$VLLM_PID" 2>/dev/null; then
        echo "ERRO: vLLM morreu durante startup. Ultimas linhas:"
        tail -50 "$VLLM_LOG"
        exit 1
    fi
    sleep "$HEALTH_POLL_SLEEP"
done

if ! healthcheck > /dev/null 2>&1; then
    echo "ERRO: vLLM nao ficou pronto no tempo limite"
    tail -80 "$VLLM_LOG"
    exit 1
fi

aiperf profile \
    --model "$MODEL" \
    --endpoint-type chat \
    --url "http://$HOST:$PORT" \
    --streaming \
    --request-count "$REQUEST_COUNT" \
    --warmup-request-count "$WARMUP_COUNT" \
    --prompt-input-tokens-mean "$ISL" \
    --prompt-output-tokens-mean "$OSL" \
    --extra-inputs ignore_eos:true \
    --output-artifact-dir "$HEAD_RESULTS"

echo "[head] benchmark concluido"
