#!/usr/bin/env bash
# Trace a process's network/fd/epoll syscalls with timestamps.
#
#   scripts/capture/strace.sh [-e TRACE] [-o DIR] -p PID [-d SECONDS]
#   scripts/capture/strace.sh [-e TRACE] [-o DIR] -- CMD [ARGS...]
#
# Default TRACE: trace=network,desc,epoll_wait,epoll_pwait (the course's standard
# view). arm64 has no epoll_wait syscall: libc implements epoll_wait() with
# epoll_pwait, so on Apple Silicon labs only epoll_pwait lines appear.
# Writes DIR/strace.txt (default captures/<timestamp>/) and prints a summary.
set -euo pipefail

trace="trace=network,desc,epoll_wait,epoll_pwait" out="" pid="" duration=10
while getopts "e:o:p:d:h" opt; do
  case "$opt" in
    e) trace="$OPTARG" ;;
    o) out="$OPTARG" ;;
    p) pid="$OPTARG" ;;
    d) duration="$OPTARG" ;;
    *) sed -n '2,10p' "$0"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ -n "$pid" ] || [ $# -gt 0 ] || { sed -n '2,10p' "$0"; exit 2; }

command -v strace >/dev/null || { echo "strace not found (run in 'just lab')" >&2; exit 127; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${out:-$ROOT/captures/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out"
log="$out/strace.txt"
if [ "$(id -u)" = 0 ]; then SUDO=""; else SUDO="sudo"; fi

status=0
if [ -n "$pid" ]; then
  echo "capture: strace -p $pid for ${duration}s -> $log" >&2
  $SUDO timeout "$duration" strace -f -tt -e "$trace" -o "$log" -p "$pid" \
    || { rc=$?; [ "$rc" -eq 124 ] || status=$rc; } # 124 = capture window ended
else
  echo "capture: strace $* -> $log" >&2
  # strace exits with the traced command's status; report it after the summary.
  $SUDO strace -f -tt -e "$trace" -o "$log" "$@" || status=$?
fi
echo "--- $(wc -l <"$log") syscalls; top 10 by count:"
grep -oE '^([0-9]+ +)?[0-9:.]+ [a-z_0-9]+\(' "$log" | grep -oE '[a-z_0-9]+\($' | sort | uniq -c | sort -rn | head -10 || true # an idle process traces nothing
exit "$status"
