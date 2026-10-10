#!/usr/bin/env bash
# Capture packets for a few seconds, save a pcap, then print it with -nn -X.
#
#   scripts/capture/tcpdump.sh [-i IFACE] [-d SECONDS] [-o DIR] [FILTER...]
#   scripts/capture/tcpdump.sh -d 5 'tcp port 8080'
#
# Defaults: -i any, -d 10, -o captures/<timestamp>/. Open the pcap in Wireshark
# for dissectors (tcp.analysis, http, http2, pgsql, ...). Linux: run in `just lab`.
set -euo pipefail

iface=any duration=10 out=""
while getopts "i:d:o:h" opt; do
  case "$opt" in
    i) iface="$OPTARG" ;;
    d) duration="$OPTARG" ;;
    o) out="$OPTARG" ;;
    *) sed -n '2,8p' "$0"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

command -v tcpdump >/dev/null || { echo "tcpdump not found (run in 'just lab')" >&2; exit 127; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${out:-$ROOT/captures/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out"
pcap="$out/tcpdump.pcap"
if [ "$(id -u)" = 0 ]; then SUDO=""; else SUDO="sudo"; fi

echo "capture: tcpdump -i $iface for ${duration}s -> $pcap" >&2
# timeout exits 124 when the capture window ends; that is success here.
$SUDO timeout "$duration" tcpdump -i "$iface" -nn -U -w "$pcap" "$@" || [ $? -eq 124 ]
$SUDO tcpdump -nn -X -r "$pcap"
