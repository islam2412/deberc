#!/usr/bin/env bash
# Ночная проверка «чутья» дуэлями (на ПК, WSL). Итоги — в $OUT.
OUT=${OUT:-/mnt/c/deberc-nn/duels.log}
cd "$(dirname "$0")" || exit 1
run() { echo "$(date '+%d.%m %H:%M') $(.build/release/BeliefDuel "$@" 2>&1 | tail -1)" >> "$OUT"; }
echo "$(date '+%d.%m %H:%M') start $(git rev-parse --short HEAD)" >> "$OUT"
run master+bl=1 master 2 2000 61
run master+bl=1+pi=0 master 2 2000 61
run master+bl=1 master 3 4000 55
run master+bl=0.5 master 2 2000 62
run master+bl=1 master 2 2000 63
run master+bl=1 master 3 4000 56
echo "$(date '+%d.%m %H:%M') done" >> "$OUT"
