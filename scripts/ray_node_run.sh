#!/bin/bash
set -euo pipefail

[[ -f flake.nix ]] || { echo "rode da raiz do projeto"; exit 1; }

. scripts/config.sh

: "${NODE_RESULTS_DIR:?NODE_RESULTS_DIR obrigatorio (definido pelo slurm_task_ray.sh)}"
: "${VENV_PATH:?VENV_PATH obrigatorio}"

NODE_HOST="$(hostname)"
mkdir -p "$NODE_RESULTS_DIR/.mplcache"
RAY_BIN="$VENV_PATH/bin/ray"
[ -x "$RAY_BIN" ] || { echo "ray nao encontrado em $RAY_BIN"; exit 1; }

export RAY_TMPDIR="$SCRATCH/ray_$SLURM_JOB_ID"
rm -rf "$RAY_TMPDIR"
mkdir -p "$RAY_TMPDIR"

"$RAY_BIN" stop --force || true


NODE_IP="$(bash scripts/get_head_ip.sh)"
export RAY_NODE_IP_ADDRESS="$NODE_IP"
export VLLM_HOST_IP="$NODE_IP"
NODE_IFACE="$(ip -o -4 addr show | awk '$4 ~ /^192\.168\./ {print $2; exit}')"
if [ -n "$NODE_IFACE" ]; then
    # Evita o Gloo escolher loopback (127.0.0.1) no init distribuido.
    export GLOO_SOCKET_IFNAME="$NODE_IFACE"
    export NCCL_SOCKET_IFNAME="$NODE_IFACE"
    export UCX_NET_DEVICES="$NODE_IFACE"
fi
echo "[$NODE_HOST] usando NODE_IP=$NODE_IP (RAY_NODE_IP_ADDRESS/VLLM_HOST_IP)"

export RAY_ADDRESS="$ip_head"

NODE_TELEMETRY_CSV="$NODE_RESULTS_DIR/telemetry.csv"
NODE_NSYS_OUT="$NODE_RESULTS_DIR/ray_trace"

# Telemetria nvidia-smi por nodo
nvidia-smi \
    --query-gpu=timestamp,index,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu,clocks.current.sm,clocks.current.memory \
    --format=csv,nounits \
    --loop-ms="$NVSMI_INTERVAL_MS" > "$NODE_TELEMETRY_CSV" &
NVSMI_PID=$!
echo "[$NODE_HOST] nvidia-smi PID=$NVSMI_PID -> $NODE_TELEMETRY_CSV"

cleanup() {
    echo "[$NODE_HOST] cleanup nvidia-smi/ray"
    [ -n "${NVSMI_PID:-}" ] && kill "$NVSMI_PID" 2>/dev/null || true
    "$RAY_BIN" stop --force 2>/dev/null || true
    wait 2>/dev/null || true
    rm -rf "$RAY_TMPDIR"
}
trap cleanup EXIT

# Comando ray symmetric-run: ele inicia ray em todos os nodos e executa o entrypoint
# apenas no head. A entrada e' o run_vllm_ray_bench.sh (vllm + aiperf).
RAY_CMD=(
    "$RAY_BIN" symmetric-run
    --address "$ip_head"
    --min-nodes "$SLURM_JOB_NUM_NODES"
    --temp-dir "$RAY_TMPDIR"
    --disable-usage-stats
    --
    bash scripts/run_vllm_ray_bench.sh
)

if [ "${NSYS:-0}" = "1" ]; then
    echo "[$NODE_HOST] nsys habilitado"

    nsys profile \
        --output="$NODE_NSYS_OUT" \
        --force-overwrite=true \
        --trace=cuda,nvtx,cublas,osrt \
        --sample=none \
        --wait=all \
        --trace-fork-before-exec=true \
        "${RAY_CMD[@]}"
else
    "${RAY_CMD[@]}"
fi
