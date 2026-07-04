# comp-sys-perf-analysis

Multi-node LLM inference benchmark traces and analysis for vLLM + Ray. Tests vary cluster, node count, parallelism strategy, and sequence length.

## Dataset: `data/data_compsys/final/trace/`

### Experiment Folder Structure

Top-level folders follow: `N{nodes}_{cluster}_{parallelism}_{seqlen}_r{run}_{jobid}/`

| Component | Values | Meaning |
|-----------|--------|---------|
| `N{nodes}` | 1, 2, 4 | Number of nodes in cluster |
| `cluster` | tupi, poti | HPC cluster name |
| `parallelism` | none, PP, TP | Single-node, pipeline-parallel, or tensor-parallel |
| `seqlen` | short, long | Sequence length workload |
| `r{run}` | r1 | Run/repetition number |
| `jobid` | integer | SLURM job ID |

Each experiment dir contains per-node subdirectories: `{cluster}{n}/` (e.g., `tupi2`, `poti1`).

### Per-Node Files

**Head node** holds the full file set; **worker nodes** hold a subset.

| File | Head | Worker | Content |
|------|------|--------|---------|
| `inputs.json` | ✓ | — | OpenAI-compat request payloads; model: Qwen/Qwen2.5-7B-Instruct |
| `telemetry.csv` | ✓ | ✓ | GPU metrics (~100ms intervals): utilization, memory, power, clocks |
| `network_telemetry.csv` | ✓ | ✓ | NIC traffic via `sar` (1s intervals): rx/tx packets, kB/sec, errors |
| `profile_export.jsonl` | ✓ | — | Per-request trace: timestamps, TTFT, inter-token latencies |
| `profile_export_aiperf.csv/.json` | ✓ | — | Aggregated summary: avg/min/max/p50/p99 latency & throughput metrics |
| `server_metrics_export.csv/.json` | ✓ | — | vLLM Prometheus metrics: KV cache usage, request counts, process stats |
| `ray_trace.nsys-rep` | ✓ | ✓ | Nsight Systems GPU trace binary |
| `vllm_server.log` | ✓ | — | vLLM server log |
| `node.log` | ✓ | ✓ | Node-level log |
| `logs/aiperf.log` | ✓ | — | AIPerf client log |
| `network/iperf3_server_nodeN.json` | ✓ | — | iperf3 server results (multi-node only) |
| `network/iperf3_client.json` | — | ✓ | iperf3 client results (multi-node only) |

**Key notes:**
- Interconnect subnet: 192.168.30.x (dedicated NIC)
- No README in trace folder; metadata lives in file headers (aiperf_version, schema_version, benchmark_id)
- CSV files use `sar` and custom formatters; JSON files use standard iperf3 and Prometheus formats
