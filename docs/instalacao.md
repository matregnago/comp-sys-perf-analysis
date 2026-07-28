# Instalação e reprodução

## Preparar o ambiente

O projeto usa [Nix flakes](https://nixos.wiki/wiki/Flakes) para as ferramentas e [uv](https://github.com/astral-sh/uv) para o ambiente Python.

Instale o Nix:

```bash
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
```

Habilite os flakes adicionando a linha abaixo em `~/.config/nix/nix.conf` ou `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

Clone o repositório e entre no ambiente de desenvolvimento:

```bash
git clone https://github.com/matregnago/vllm-parallelism-benchmark.git
cd vllm-parallelism-benchmark
nix develop .#tools
```

## Rodar os experimentos (PCAD)

Os experimentos são lançados como jobs Slurm: [`scripts/submit_jobs.sh`](../scripts/submit_jobs.sh) lê o desenho experimental de [`projeto_experimental.csv`](../projeto_experimental.csv) e submete um job ([`slurm/benchmark.slurm`](../slurm/benchmark.slurm)) por experimento. Os parâmetros gerais (modelo, carga, telemetria) ficam em [`scripts/config.sh`](../scripts/config.sh).

```bash
bash scripts/submit_jobs.sh
```

É necessário um arquivo `.env` na raiz com o `HF_TOKEN` (token do Hugging Face), conforme o `.env.example`.

Instruções detalhadas de acesso e configuração do PCAD estão em [`pcad.md`](pcad.md).

## Analisar os dados

Os notebooks usam o ambiente virtual do `uv`:

```bash
uv sync --extra dev
source .venv/bin/activate
jupyter notebook
```

O fluxo de análise é: `data_preprocessing.ipynb` consolida os dados brutos em `data_processed/`, e os demais notebooks (`inference_analysis`, `concurrency_analysis`, `communication_analysis`, `network_analysis`, `gpu_telemetry`, `doe`) geram as figuras em `figures/`.

## Relatório e slides

Para compilar o relatório em PDF:

```bash
cd tex
latexmk -pdf main.tex
```

Os slides são escritos em Markdown e compilados com o [Marp](https://marp.app):

```bash
cd slides/proposta
marp --pdf proposta.md --allow-local-files
```
