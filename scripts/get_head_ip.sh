#!/bin/bash
set -euo pipefail

{ hostname -I 2>/dev/null || hostname -i; } \
    | tr ' ' '\n' \
    | grep -m1 '^192\.168\.'
