#!/usr/bin/env bash
# Snapshot socket state repeatedly: watch queues, windows and states change.
#
#   scripts/capture/ss-watch.sh [-i SECONDS] [-n COUNT] [-o DIR] [SS-FILTER...]
#   scripts/capture/ss-watch.sh -i 0.5 -n 20 'sport = :8080'
#
# Each snapshot is `ss -tnip` (TCP, numeric, internals, processes): Recv-Q/Send-Q,
# cwnd, rtt, rcv_space. Appends to DIR/ss.txt (default captures/<timestamp>/).
set -euo pipefail

interval=1 count=10 out=""
while getopts "i:n:o:h" opt; do
  case "$opt" in
    i) interval="$OPTARG" ;;
    n) count="$OPTARG" ;;
    o) out="$OPTARG" ;;
    *) sed -n '2,8p' "$0"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${out:-$ROOT/captures/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out"
log="$out/ss.txt"
command -v ss >/dev/null || { echo "ss not found (Linux only: run in 'just lab')" >&2; exit 127; }

i=0
while [ "$i" -lt "$count" ]; do
  {
    echo "=== $(date +%H:%M:%S.%N | cut -c1-12) snapshot $((i + 1))/$count"
    ss -tnip "$@"
  } | tee -a "$log"
  i=$((i + 1))
  if [ "$i" -lt "$count" ]; then sleep "$interval"; fi
done
echo "capture: $count snapshots -> $log" >&2
