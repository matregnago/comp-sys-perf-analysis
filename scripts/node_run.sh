#!/bin/bash
#
# node_run.sh - roda por nodo (dentro do .#default). Fixa a interface de rede
# interna (192.168.*) para Ray/NCCL/Gloo, mede a banda com iperf3 (multi-node),
# inicia a telemetria (nvidia-smi + sar) e sobe o `ray symmetric-run` -- opcionalmente
# sob o nsys -- com o head_benchmark.sh como entrypoint (executado so no head).
set -euo pipefail

[[ -f flake.nix ]] || { echo "rode da raiz do projeto"; exit 1; }

. scripts/config.sh

: "${NODE_RESULTS_DIR:?NODE_RESULTS_DIR obrigatorio (definido pelo node_setup.sh)}"
: "${VENV_PATH:?VENV_PATH obrigatorio}"

NODE_HOST="$(hostname)"
mkdir -p "$NODE_RESULTS_DIR/.mplcache"
RAY_BIN="$VENV_PATH/bin/ray"
[ -x "$RAY_BIN" ] || { echo "ray nao encontrado em $RAY_BIN"; exit 1; }

export RAY_TMPDIR="$SCRATCH/ray_$SLURM_JOB_ID"
rm -rf "$RAY_TMPDIR"
mkdir -p "$RAY_TMPDIR"

# Roots de config/cache do vLLM (definidos em config.sh) precisam existir neste
# nodo; os workers Ray herdam VLLM_CONFIG_ROOT/VLLM_CACHE_ROOT do env deste processo.
mkdir -p "$VLLM_CONFIG_ROOT" "$VLLM_CACHE_ROOT"

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

    export NCCL_DEBUG=INFO
    export NCCL_DEBUG_SUBSYS=INIT,NET
    echo "[$NODE_HOST] NCCL_DEBUG ativado na interface $NODE_IFACE"
fi
echo "[$NODE_HOST] usando NODE_IP=$NODE_IP (RAY_NODE_IP_ADDRESS/VLLM_HOST_IP)"

export RAY_ADDRESS="$ip_head"

# iperf3 entre nodos (opt-in, multi-node apenas). Roda ANTES de iniciar
# nvidia-smi e sar para nao poluir a telemetria com o trafego do teste.
# Head (SLURM_NODEID=0) sobe servidor; workers conectam em sequencia
# (escalonado por NODEID) para nao saturarem o head em paralelo.
if [ "${IPERF:-0}" = "1" ] && [ "${SLURM_JOB_NUM_NODES:-1}" -gt 1 ]; then
    : "${HEAD_IP:?HEAD_IP obrigatorio para iperf3 (exportado pelo benchmark.slurm)}"
    NETDIR="$NODE_RESULTS_DIR/network"
    mkdir -p "$NETDIR"
    IPERF_PORT="${IPERF_PORT:-5201}"
    IPERF_DURATION="${IPERF_DURATION:-10}"
    IPERF_PARALLEL="${IPERF_PARALLEL:-4}"
    IPERF_SLOT=$(( IPERF_DURATION + 5 ))                            # janela por cliente
    IPERF_BUDGET=$(( (SLURM_JOB_NUM_NODES - 1) * IPERF_SLOT + 10 )) # tempo total

    if [ "${SLURM_NODEID:-0}" = "0" ]; then
        echo "[$NODE_HOST] iperf3: servidor em $HEAD_IP:$IPERF_PORT, $((SLURM_JOB_NUM_NODES - 1)) clientes em sequencia"
        for i in $(seq 1 $((SLURM_JOB_NUM_NODES - 1))); do
            timeout "$(( IPERF_SLOT + 10 ))" \
                iperf3 -s -1 -B "$HEAD_IP" -p "$IPERF_PORT" \
                -J --logfile "$NETDIR/iperf3_server_node${i}.json" \
                || echo "[$NODE_HOST] iperf3 server slot=$i falhou (ignorando)"
        done
        echo "[$NODE_HOST] iperf3: servidor finalizado"
    else
        WAIT=$(( (SLURM_NODEID - 1) * IPERF_SLOT + 3 ))
        echo "[$NODE_HOST] iperf3: aguarda ${WAIT}s e conecta em $HEAD_IP:$IPERF_PORT"
        sleep "$WAIT"
        timeout "$(( IPERF_DURATION + 30 ))" \
            iperf3 -c "$HEAD_IP" -p "$IPERF_PORT" \
            -t "$IPERF_DURATION" -P "$IPERF_PARALLEL" \
            -J --logfile "$NETDIR/iperf3_client.json" \
            || echo "[$NODE_HOST] iperf3 client falhou (ignorando)"
        echo "[$NODE_HOST] iperf3: cliente finalizado"
        # Workers que terminaram cedo esperam o orcamento total
        # para todos chegarem juntos no symmetric-run.
        REMAINING=$(( IPERF_BUDGET - WAIT - IPERF_DURATION ))
        if [ "$REMAINING" -gt 0 ]; then
            sleep "$REMAINING"
        fi
    fi
fi

NODE_TELEMETRY_CSV="$NODE_RESULTS_DIR/telemetry.csv"
NODE_NSYS_OUT="$NODE_RESULTS_DIR/ray_trace"
NODE_NET_CSV="$NODE_RESULTS_DIR/network_telemetry.csv" # telemetria de rede (sar)

# Telemetria nvidia-smi por nodo
nvidia-smi \
    --query-gpu=timestamp,index,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu,clocks.current.sm,clocks.current.memory \
    --format=csv,nounits \
    --loop-ms="$NVSMI_INTERVAL_MS" > "$NODE_TELEMETRY_CSV" &
NVSMI_PID=$!
echo "[$NODE_HOST] nvidia-smi PID=$NVSMI_PID -> $NODE_TELEMETRY_CSV"

if [ -n "$NODE_IFACE" ]; then
    sar -n DEV 1 | grep --line-buffered "$NODE_IFACE" | awk '{print strftime("%Y-%m-%d %H:%M:%S"), $0; fflush()}' > "$NODE_NET_CSV" &
    SAR_PID=$!
    echo "[$NODE_HOST] sar (rede) PID=$SAR_PID -> $NODE_NET_CSV"
fi

cleanup() {
    echo "[$NODE_HOST] cleanup nvidia-smi, sar e ray"
    [ -n "${NVSMI_PID:-}" ] && kill "$NVSMI_PID" 2>/dev/null || true
    [ -n "${SAR_PID:-}" ] && kill "$SAR_PID" 2>/dev/null || true # garante que o sar encerre
    "$RAY_BIN" stop --force 2>/dev/null || true
    wait 2>/dev/null || true
    rm -rf "$RAY_TMPDIR"
}
trap cleanup EXIT

# Comando ray symmetric-run: ele inicia ray em todos os nodos e executa o entrypoint
# apenas no head. A entrada e' o head_benchmark.sh (vllm + aiperf).
RAY_CMD=(
    "$RAY_BIN" symmetric-run
    --address "$ip_head"
    --min-nodes "$SLURM_JOB_NUM_NODES"
    --temp-dir "$RAY_TMPDIR"
    --disable-usage-stats
    --
    bash scripts/head_benchmark.sh
)

if [ "${NSYS:-0}" = "1" ]; then
    echo "[$NODE_HOST] nsys habilitado"

    nsys profile \
        --output="$NODE_NSYS_OUT" \
        --force-overwrite=true \
        --trace=cuda \
        --sample=none \
        --wait=all \
        --trace-fork-before-exec=true \
        "${RAY_CMD[@]}"
else
    "${RAY_CMD[@]}"
fi
