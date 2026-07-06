#!/bin/bash

# Sobe o `vllm serve` com a topologia TP/PP, espera o /v1/models responder e entao
# roda o `aiperf profile` para medir a inferencia.
set -euo pipefail

[[ -f flake.nix ]] || { echo "rode da raiz do projeto"; exit 1; }

. scripts/config.sh

: "${RESULTS_DIR:?RESULTS_DIR obrigatorio}"
: "${VIRTUAL_ENV:?VIRTUAL_ENV obrigatorio (venv ativado pelo shellHook do flake)}"
: "${ip_head:?ip_head obrigatorio (IP:porta do head Ray, definido pelo benchmark.slurm)}"

export RAY_ADDRESS="$ip_head"

if [ -z "${VLLM_HOST_IP:-}" ]; then
    HEAD_IP="${ip_head%%:*}"
    export VLLM_HOST_IP="$HEAD_IP"
fi

export MPLCONFIGDIR="${MPLCONFIGDIR:-$RESULTS_DIR/.mplcache}"

HEAD_HOST="$(hostname)"
HEAD_RESULTS="$RESULTS_DIR/$HEAD_HOST"
mkdir -p "$HEAD_RESULTS"
mkdir -p "$MPLCONFIGDIR"

VLLM_LOG="$HEAD_RESULTS/vllm_server.log"

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

if [ "${ENFORCE_EAGER:-0}" = "1" ]; then
    VLLM_ARGS+=(--enforce-eager)
fi

if [ -n "${MAX_NUM_SEQS:-}" ]; then
    VLLM_ARGS+=(--max-num-seqs "$MAX_NUM_SEQS")
fi

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

run_aiperf() {
    local conc="$1" out_dir="$2" req="$3" warm="$4"
    mkdir -p "$out_dir"
    local args=(
        --model "$MODEL"
        --endpoint-type chat
        --url "http://$HOST:$PORT"
        --streaming
        --request-count "$req"
        --warmup-request-count "$warm"
        --prompt-input-tokens-mean "$ISL"
        --prompt-output-tokens-mean "$OSL"
        --extra-inputs ignore_eos:true
        --output-artifact-dir "$out_dir"
    )
    [ -n "$conc" ] && args+=(--concurrency "$conc")
    echo "[head] aiperf concurrency=${conc:-default} req=$req warmup=$warm -> $out_dir"
    aiperf profile "${args[@]}"
}

if [ -n "${CONCURRENCY_LEVELS:-}" ]; then
    echo "[head] varredura de concorrencia: [$CONCURRENCY_LEVELS] -> $HEAD_RESULTS/concurrency_*"
    MAX_REQUESTS="${MAX_REQUESTS:-640}"
    for c in $CONCURRENCY_LEVELS; do
        req=$(( c * REQUESTS_PER_CONCURRENCY ))
        [ "$req" -lt "$REQUEST_COUNT" ] && req="$REQUEST_COUNT"
        [ "$req" -gt "$MAX_REQUESTS" ] && req="$MAX_REQUESTS"
        warm="$c"
        [ "$warm" -lt "$WARMUP_COUNT" ] && warm="$WARMUP_COUNT"
        out="$HEAD_RESULTS/concurrency_$(printf '%03d' "$c")"
        run_aiperf "$c" "$out" "$req" "$warm"
    done
else
    echo "[head] aiperf (run unico, sem varredura) -> $HEAD_RESULTS"
    run_aiperf "" "$HEAD_RESULTS" "$REQUEST_COUNT" "$WARMUP_COUNT"
fi

echo "[head] benchmark concluido"
