#!/bin/bash
# Imprime o IP da rede 192.168.* da maquina local (rede interna do PCAD).
# Funciona com hostname do glibc (-I) e com busybox (-i, dentro do FHS).
set -euo pipefail

{ hostname -I 2>/dev/null || hostname -i; } \
    | tr ' ' '\n' \
    | grep -m1 '^192\.168\.'
