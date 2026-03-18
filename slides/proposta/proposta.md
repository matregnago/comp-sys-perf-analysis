---
marp: true
theme: gaia
paginate: true
size: 16:9
---
# Análise de Desempenho da Inferência  
## de um Modelo de Linguagem Distribuído em Múltiplas GPUs

Rafael Silva de Souza  
Matheus Augusto Tregnago  
Lucas Fraga Balbinot  

Universidade Federal do Rio Grande do Sul  
Instituto de Informática  

---

# Motivação

Modelos de linguagem de grande porte (LLMs) tornaram-se essenciais em diversas aplicações de IA:

- Assistentes virtuais
- Sistemas de diálogo
- Tradução automática
- Geração de texto

Esses modelos possuem **bilhões de parâmetros**, exigindo grande capacidade computacional.

---

# Modelos de Linguagem Modernos

LLMs modernos são baseados na arquitetura **Transformer**.

**Principais características**

- Uso de **mecanismos de atenção (attention)**
- Processamento paralelo de sequências
- Escalabilidade para bilhões de parâmetros


---

# Problema

A execução de modelos grandes apresenta desafios:

- Alto consumo de memória
- Grande número de operações matriciais
- Necessidade de **alto paralelismo computacional**

Mesmo durante **inferência**, o custo computacional é elevado.

---

# O que é Inferência?

Inferência é o processo de **utilizar um modelo já treinado para gerar uma saída**.

Etapas principais:

1. Entrada de texto (prompt)
2. Tokenização
3. Execução das camadas do modelo
4. Predição do próximo token
5. Geração da resposta

---

# Por que usar GPUs?

GPUs são ideais para aprendizado profundo porque:

- Executam **operações matriciais em paralelo**
- Possuem alta largura de banda de memória
- São otimizadas para álgebra linear

Bibliotecas utilizadas:

- CUDA
- cuBLAS
- PyTorch

---

# Modelo Utilizado

Modelo analisado:

**Llama 3.1 8B**

Características:

- Aproximadamente **8 bilhões de parâmetros**
- Arquitetura Transformer
- Aplicações em processamento de linguagem natural

---

# Ambiente Experimental

Experimentos realizados no ambiente:

**PCAD – Plataforma de Computação de Alto Desempenho**  
Universidade Federal do Rio Grande do Sul

Infraestrutura:

- GPUs NVIDIA
- CUDA
- Ferramentas de profiling

---

# Ferramentas de Análise

Ferramentas utilizadas para coleta de métricas:

- NVIDIA Nsight Systems
- NVIDIA Nsight Compute
- nvidia-smi

Essas ferramentas permitem observar:

- utilização da GPU
- tempo de execução de kernels CUDA
- uso de memória

---

# Métricas de Desempenho

### Latência

Tempo total para gerar uma resposta:

latency = t_fim - t_inicio


---

### Throughput

Número de tokens gerados por segundo:

throughput = tokens / tempo


---

# Métricas de GPU

Serão analisados:

- utilização da GPU
- uso de memória
- largura de banda de memória
- tempo de execução de kernels CUDA

Objetivo: identificar **gargalos de hardware**.

---

# Escalabilidade

Para avaliar o paralelismo será medido o **speedup**:

Speedup(N) = T(1) / T(N)


onde:

- T(1) = tempo usando 1 GPU
- T(N) = tempo usando N GPUs

---

# Eficiência Paralela

A eficiência do paralelismo será calculada por:

Efficiency(N) = Speedup(N) / N


Permite avaliar se o uso de múltiplas GPUs é eficiente.

---

# Planejamento Experimental

Parâmetros analisados:

- número de GPUs
- tamanho do prompt
- número de tokens gerados
- tamanho do batch de inferência

Cada experimento será repetido várias vezes para reduzir variabilidade.

---

# Resultados Esperados

Espera-se identificar:

- gargalos de execução
- impacto do paralelismo em GPUs
- limites de escalabilidade do modelo

---

# Contribuições

Este trabalho busca contribuir para:

- melhor compreensão da execução de **LLMs em HPC**
- análise de desempenho de inferência
- otimização de execução em múltiplas GPUs

---

# Obrigado!

Perguntas?