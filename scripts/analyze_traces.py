#!/usr/bin/env python3
"""Separa comunicacao (NCCL) de computacao nos traces nsys dos experimentos.

Para cada run em data/N*/<rank>/ray_trace.nsys-rep:
  - roda `nsys stats --report cuda_gpu_kern_sum` (reaproveita o .sqlite ja exportado);
  - classifica cada kernel: nome contem "nccl" => comunicacao, senao computacao;
  - soma o Total Time (ns) de cada classe e calcula a fracao comm/comp por rank;
  - agrega por run e cruza com aiperf (ITL/throughput), sar (%ifutil) e iperf3 (teto).

Saida: data_processed/comm_comp.csv (+ comm_comp_per_rank.csv) e figuras em
figures/communication/. Roda onde o `nsys` esteja no PATH (ex.: nixw nix develop .#default,
ou local). So precisa de stdlib; matplotlib e' opcional (apenas para as figuras).

Metodo validado em docs/analise-comunicacao-computacao.md. Com 1 GPU/no os kernels
serializam na mesma GPU, entao o tempo de kernel NCCL ~= comunicacao exposta (wall-clock).
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

KERN_REPORT = "cuda_gpu_kern_sum"


# --------------------------------------------------------------------------- #
# Classificacao de kernels
# --------------------------------------------------------------------------- #
def is_comm(name: str) -> bool:
    return "nccl" in name.lower()


def classify_collective(name: str) -> str:
    n = name.lower()
    if "allreduce" in n:
        return "AllReduce"
    if "allgather" in n:
        return "AllGather"
    if "reducescatter" in n or "reduce_scatter" in n:
        return "ReduceScatter"
    if "broadcast" in n:
        return "Broadcast"
    if "sendrecv" in n or "send" in n or "recv" in n or "p2p" in n:
        return "SendRecv"
    if "reduce" in n:
        return "Reduce"
    return "OtherNCCL"


# --------------------------------------------------------------------------- #
# nsys
# --------------------------------------------------------------------------- #
def run_kern_sum(trace: Path, force: bool) -> str | None:
    """Retorna o stdout CSV do `nsys stats cuda_gpu_kern_sum`, ou None se falhar."""
    cmd = ["nsys", "stats", "--report", KERN_REPORT, "--format", "csv", str(trace)]
    if force:
        cmd.insert(2, "--force-export=true")
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError:
        sys.exit("ERRO: `nsys` nao encontrado no PATH. Rode dentro de um shell com o "
                 "Nsight Systems (ex.: nixw nix develop .#default).")
    if proc.returncode != 0:
        print(f"  [warn] nsys falhou em {trace}: {proc.stderr.strip()[:200]}")
        return None
    return proc.stdout


def parse_kern_sum(csv_text: str):
    """Soma comm/comp (ns) e tempo por coletivo a partir do CSV do nsys."""
    lines = csv_text.splitlines()
    start = next((i for i, l in enumerate(lines) if l.startswith("Time (%)")), None)
    if start is None:
        return None
    comm = comp = 0.0
    coll = defaultdict(float)
    for row in csv.DictReader(lines[start:]):
        try:
            t = float(row["Total Time (ns)"])
        except (KeyError, ValueError, TypeError):
            continue
        name = row.get("Name", "")
        if is_comm(name):
            comm += t
            coll[classify_collective(name)] += t
        else:
            comp += t
    dominant = max(coll, key=coll.get) if coll else None
    return {"comm_ns": comm, "comp_ns": comp, "dominant": dominant, "coll": dict(coll)}


# --------------------------------------------------------------------------- #
# Metadados do run e fontes auxiliares
# --------------------------------------------------------------------------- #
def parse_run_name(name: str) -> dict:
    parts = name.split("_")
    out = {"n_gpus": None, "node": None, "strategy": None, "workload": None}
    try:
        out["n_gpus"] = int(re.sub(r"\D", "", parts[0]))
        out["node"] = parts[1]
        out["strategy"] = parts[2]
        out["workload"] = parts[3]
    except (IndexError, ValueError):
        pass
    return out


def aiperf_metrics(head_dir: Path) -> dict:
    p = head_dir / "profile_export_aiperf.json"
    if not p.exists():
        return {}
    try:
        d = json.loads(p.read_text())
    except Exception:
        return {}

    def g(metric, field="avg"):
        m = d.get(metric)
        return m.get(field) if isinstance(m, dict) else None

    return {
        "throughput_req_s": g("request_throughput"),
        "itl_ms": g("inter_token_latency"),
        "ttft_ms": g("time_to_first_token"),
        "latency_ms": g("request_latency"),
        "out_tok_throughput": g("output_token_throughput_per_user"),
    }


def peak_ifutil(run_dir: Path):
    """Maior %ifutil (ultima coluna do sar -n DEV) entre todos os nodos do run."""
    peak = None
    for p in run_dir.glob("*/network_telemetry.csv"):
        try:
            for line in p.read_text(errors="ignore").splitlines():
                toks = line.split()
                if not toks:
                    continue
                try:
                    val = float(toks[-1])
                except ValueError:
                    continue
                if peak is None or val > peak:
                    peak = val
        except Exception:
            continue
    return peak


def iperf3_gbps(run_dir: Path):
    """Media da banda medida (Gbit/s) entre os clientes iperf3 do run."""
    vals = []
    for p in run_dir.glob("*/network/iperf3_client.json"):
        try:
            d = json.loads(p.read_text())
            bps = d["end"]["sum_received"]["bits_per_second"]
            vals.append(bps / 1e9)
        except Exception:
            continue
    return sum(vals) / len(vals) if vals else None


def find_head_dir(rank_dirs: list[Path]) -> Path | None:
    """Rank 0 = o que hospeda o aiperf (tem profile_export_aiperf.json)."""
    for d in rank_dirs:
        if (d / "profile_export_aiperf.json").exists():
            return d
    return None


# --------------------------------------------------------------------------- #
# Pipeline por run
# --------------------------------------------------------------------------- #
def analyze_run(run_dir: Path, force: bool, require_aiperf: bool):
    rank_dirs = sorted(p.parent for p in run_dir.glob("*/ray_trace.nsys-rep"))
    if not rank_dirs:
        return None, []

    head = find_head_dir(rank_dirs)
    if require_aiperf and head is None:
        print(f"  [skip] {run_dir.name}: sem profile_export_aiperf.json "
              f"(inferencia nao rodou)")
        return None, []

    per_rank = []
    for d in rank_dirs:
        trace = d / "ray_trace.nsys-rep"
        print(f"  - {run_dir.name}/{d.name}: nsys stats ...", flush=True)
        text = run_kern_sum(trace, force)
        if text is None:
            continue
        parsed = parse_kern_sum(text)
        if parsed is None:
            print(f"    [warn] sem secao cuda_gpu_kern_sum em {trace.name}")
            continue
        comm, comp = parsed["comm_ns"], parsed["comp_ns"]
        tot = comm + comp
        per_rank.append({
            "run": run_dir.name,
            "rank": d.name,
            "is_head": d == head,
            "comm_s": comm / 1e9,
            "comp_s": comp / 1e9,
            "gpu_s": tot / 1e9,
            "comm_pct": 100 * comm / tot if tot else None,
            "dominant_collective": parsed["dominant"],
        })

    if not per_rank:
        return None, []

    meta = parse_run_name(run_dir.name)
    head_row = next((r for r in per_rank if r["is_head"]), per_rank[0])
    comm_pcts = [r["comm_pct"] for r in per_rank if r["comm_pct"] is not None]

    summary = {
        "run": run_dir.name,
        **meta,
        "n_ranks": len(per_rank),
        "comm_pct_head": head_row["comm_pct"],
        "comm_pct_mean": sum(comm_pcts) / len(comm_pcts) if comm_pcts else None,
        "comp_pct_head": (100 - head_row["comm_pct"]) if head_row["comm_pct"] is not None else None,
        "gpu_s_head": head_row["gpu_s"],
        "dominant_collective": head_row["dominant_collective"],
        "ifutil_peak": peak_ifutil(run_dir),
        "iperf3_gbps": iperf3_gbps(run_dir),
    }
    if head is not None:
        summary.update(aiperf_metrics(head))
    return summary, per_rank


# --------------------------------------------------------------------------- #
# Figuras
# --------------------------------------------------------------------------- #
def make_figures(rows: list[dict], outdir: Path):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception:
        print("[figuras] matplotlib indisponivel; pulando.")
        return

    outdir.mkdir(parents=True, exist_ok=True)
    rows = [r for r in rows if r.get("comm_pct_head") is not None]
    if not rows:
        return

    order = {"none": 0, "TP": 1, "PP": 2}
    rows = sorted(rows, key=lambda r: (order.get(r["strategy"], 9),
                                       r["n_gpus"] or 0, r["workload"] or ""))

    # 1) Barras empilhadas comm/comp por configuracao
    labels = [f"{r['node']} N{r['n_gpus']}\n{r['strategy']} {r['workload']}" for r in rows]
    comm = [r["comm_pct_head"] for r in rows]
    comp = [100 - c for c in comm]
    x = range(len(rows))
    fig, ax = plt.subplots(figsize=(max(7, len(rows) * 1.1), 4.5))
    ax.bar(x, comm, label="Comunicacao (NCCL)", color="#d1495b")
    ax.bar(x, comp, bottom=comm, label="Computacao", color="#3a7ca5")
    ax.set_xticks(list(x))
    ax.set_xticklabels(labels, fontsize=8)
    ax.set_ylabel("% do tempo de GPU")
    ax.set_ylim(0, 100)
    ax.set_title("Comunicacao vs. computacao por configuracao (rank 0)")
    ax.legend(loc="lower right")
    for i, c in enumerate(comm):
        ax.text(i, c / 2, f"{c:.0f}%", ha="center", va="center", color="white", fontsize=8)
    fig.tight_layout()
    fig.savefig(outdir / "comm-comp-stacked.png", dpi=150, bbox_inches="tight")
    plt.close(fig)

    # 2) Fracao de comunicacao vs numero de GPUs (por estrategia/workload)
    fig, ax = plt.subplots(figsize=(6, 4.5))
    series = defaultdict(list)
    for r in rows:
        if r["strategy"] in ("TP", "PP"):
            series[(r["strategy"], r["workload"])].append((r["n_gpus"], r["comm_pct_head"]))
    for (strat, wl), pts in sorted(series.items()):
        pts.sort()
        ax.plot([p[0] for p in pts], [p[1] for p in pts],
                marker="o", label=f"{strat} {wl}")
    ax.set_xlabel("numero de GPUs (= nodos, 1 GPU/no)")
    ax.set_ylabel("% comunicacao (rank 0)")
    ax.set_ylim(0, 100)
    ax.set_title("Escalabilidade da fracao de comunicacao")
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(outdir / "comm-fraction-vs-gpus.png", dpi=150, bbox_inches="tight")
    plt.close(fig)

    print(f"[figuras] salvas em {outdir}/")


# --------------------------------------------------------------------------- #
def _to_float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _to_int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return None


def load_summary_csv(path: Path) -> list[dict]:
    """Recarrega comm_comp.csv (para gerar figuras sem re-rodar o nsys)."""
    rows = []
    num = ("comm_pct_head", "comm_pct_mean", "comp_pct_head", "gpu_s_head",
           "throughput_req_s", "itl_ms", "ttft_ms", "latency_ms",
           "ifutil_peak", "iperf3_gbps")
    with path.open() as f:
        for r in csv.DictReader(f):
            for k in num:
                r[k] = _to_float(r.get(k))
            r["n_gpus"] = _to_int(r.get("n_gpus"))
            rows.append(r)
    return rows


def write_csv(path: Path, rows: list[dict], fields: list[str]):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in fields})


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", type=Path, default=Path("data"),
                    help="diretorio raiz dos runs (default: data)")
    ap.add_argument("--out", type=Path, default=Path("data_processed"),
                    help="diretorio de saida dos CSVs (default: data_processed)")
    ap.add_argument("--figdir", type=Path, default=Path("figures/communication"),
                    help="diretorio das figuras")
    ap.add_argument("--only", default=None,
                    help="processa apenas runs cujo nome contem esta substring")
    ap.add_argument("--force-export", action="store_true",
                    help="re-exporta o .sqlite do nsys (default: reaproveita)")
    ap.add_argument("--include-no-aiperf", action="store_true",
                    help="inclui runs sem aiperf (traces de startup sem inferencia)")
    ap.add_argument("--no-figures", action="store_true")
    ap.add_argument("--figures-from", type=Path, default=None,
                    help="gera so as figuras a partir de um comm_comp.csv existente "
                         "(nao roda o nsys). Use dentro de `nix develop .#tools`.")
    args = ap.parse_args()

    if args.figures_from:
        make_figures(load_summary_csv(args.figures_from), args.figdir)
        return

    run_dirs = sorted(p for p in args.data.glob("N*") if p.is_dir())
    if args.only:
        run_dirs = [p for p in run_dirs if args.only in p.name]
    if not run_dirs:
        sys.exit(f"Nenhum run encontrado em {args.data}/ (filtro={args.only!r}).")

    summaries, per_rank_all = [], []
    for run_dir in run_dirs:
        summary, per_rank = analyze_run(run_dir, args.force_export,
                                        require_aiperf=not args.include_no_aiperf)
        if summary:
            summaries.append(summary)
            per_rank_all.extend(per_rank)
            print(f"  => {run_dir.name}: comm(head)={summary['comm_pct_head']:.1f}%  "
                  f"coletivo={summary['dominant_collective']}  "
                  f"ifutil_pico={summary['ifutil_peak']}  ITL={summary.get('itl_ms')}")

    if not summaries:
        sys.exit("Nenhum run com dados utilizaveis (use --include-no-aiperf para ver startup-only).")

    summary_fields = [
        "run", "node", "n_gpus", "strategy", "workload", "n_ranks",
        "comm_pct_head", "comm_pct_mean", "comp_pct_head", "gpu_s_head",
        "dominant_collective", "throughput_req_s", "itl_ms", "ttft_ms",
        "latency_ms", "out_tok_throughput", "ifutil_peak", "iperf3_gbps",
    ]
    per_rank_fields = ["run", "rank", "is_head", "comm_s", "comp_s", "gpu_s",
                       "comm_pct", "dominant_collective"]

    write_csv(args.out / "comm_comp.csv", summaries, summary_fields)
    write_csv(args.out / "comm_comp_per_rank.csv", per_rank_all, per_rank_fields)
    print(f"\nSalvo: {(args.out / 'comm_comp.csv').resolve()}  ({len(summaries)} runs)")
    print(f"Salvo: {(args.out / 'comm_comp_per_rank.csv').resolve()}  ({len(per_rank_all)} ranks)")

    if not args.no_figures:
        make_figures(summaries, args.figdir)


if __name__ == "__main__":
    main()
