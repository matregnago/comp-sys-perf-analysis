# Passos para rodar o projeto

1. Instalar o `Nix`:

```bash
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
```

2. Habilitar os flakes:

Adicione a linha a seguir em `~/.config/nix/nix.conf` ou `/etc/nix/nix.conf`:

```bash
experimental-features = nix-command flakes
```

3. Clonar o repositório:

```bash
git clone https://github.com/matregnago/comp-sys-perf-analysis.git
cd comp-sys-perf-analysis
```

4. Entrar no ambiente do `nix`:

```bash
nix develop
```

## Slides

Os slides estão localizados na pasta `slides`. Eles são escritos em `markdown` e compilados para pdf com o [Marp](https://marp.app) a partir dos seguintes comandos:

```bash
cd slides/proposta
marp --pdf proposta.md --allow-local-files
```
Isso gera um arquivo chamado `proposta.pdf`.

## Jupyter Notebook

Para rodar o `Jupyter Notebook` utilize o comando:

```bash
jupyter notebook analysis.ipynb
```

## Relatório LaTeX

Para compilar o relatório `main.tex` para `pdf`, utilize os seguintes comandos:

```bash
cd tex
latexmk -pdf main.tex
```
