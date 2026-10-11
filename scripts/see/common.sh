# shellcheck shell=bash
# Helpers for demos/<mm>/<ll>/see.sh, the reproducible half of every "See It".
#
# A see.sh looks like this:
#
#   #!/usr/bin/env bash
#   EXPECT='win 0'                      # regex; some output line must match
#   source "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/see/common.sh"
#   require_tool tcpdump ss
#   start_bg python3 "$SEE_ROOT/demos/00/03/python/main.py" --port 9000
#   server=$SEE_BG_PID                  # its pid (it runs in its own process group)
#   wait_port 9000
#   see_run ss -tni 'sport = :9000'     # output is shown AND logged
#   stop_bg "$server"                   # or wait_bg "$server" 10 if it exits by itself
#   expect_match                        # exit 0 if EXPECT matched, else 1
#
# Start every background process with start_bg: on any exit, see_cleanup stops each
# one and its children with a bounded TERM-then-KILL, so a see.sh never hangs or leaks.
#
# Runs as root in the lab (`just see`) and via sudo on the CI runner.

set -euo pipefail

# shellcheck disable=SC2034  # SEE_ROOT and SUDO are for the sourcing see.sh
SEE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEE_LOG="$(mktemp "${TMPDIR:-/tmp}/see.XXXXXX")"
SEE_PIDS=""
# shellcheck disable=SC2034
if [ "$(id -u)" = 0 ]; then SUDO=""; else SUDO="sudo"; fi

SEE_BG_PID=""

# see_alive PID : true while PID is running (a reaped or zombie process counts as gone).
see_alive() {
  [ -r "/proc/$1/status" ] && ! grep -q '^State:[[:space:]]*Z' "/proc/$1/status" 2>/dev/null
}

# see_forget PID : drop a reaped pid from SEE_PIDS, so cleanup never signals a reused pid.
see_forget() {
  local p kept=""
  for p in $SEE_PIDS; do [ "$p" = "$1" ] || kept="$kept $p"; done
  SEE_PIDS="$kept"
}

# stop_bg PID [SECONDS] : TERM a start_bg process and its process group (strace and its
# tracee, a bash -c pipeline), wait at most SECONDS (default 3), then KILL; always reaps.
stop_bg() {
  local pid="$1" deadline=$((SECONDS + ${2:-3}))
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  while see_alive "$pid" && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.1; done
  kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  see_forget "$pid"
}

# wait_bg PID [SECONDS] : wait for a start_bg process to finish on its own, at most
# SECONDS (default 10). Returns 0 if it finished, 1 if it had to be stopped.
wait_bg() {
  local pid="$1" deadline=$((SECONDS + ${2:-10}))
  while see_alive "$pid"; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "see: pid $pid still running after ${2:-10}s; stopping it" >&2
      stop_bg "$pid"
      return 1
    fi
    sleep 0.1
  done
  wait "$pid" 2>/dev/null || true
  see_forget "$pid"
}

# Every start_bg process is stopped (bounded, never an open-ended wait) on any exit path.
see_cleanup() {
  local pid
  for pid in $SEE_PIDS; do stop_bg "$pid" 2; done
  rm -f "$SEE_LOG"
}
trap see_cleanup EXIT

# require_tool TOOL... : fail fast (exit 127) naming the missing tool.
require_tool() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "see: '$tool' not found. Run this inside the lab: just see <mm>/<ll>" >&2
      exit 127
    fi
  done
}

# see_run CMD... : run a command, show its output and append it to the log.
see_run() {
  echo "\$ $*" | tee -a "$SEE_LOG"
  "$@" 2>&1 | tee -a "$SEE_LOG"
}

# see_log TEXT... : append text (e.g. the contents of a capture file) to the log.
see_log() { printf '%s\n' "$*" | tee -a "$SEE_LOG"; }

# start_bg CMD... : start a background process in its own process group, record its pid in
# SEE_BG_PID, and stop it (with everything it spawned) automatically on exit.
start_bg() {
  if command -v setsid >/dev/null 2>&1; then setsid "$@" & else "$@" & fi
  SEE_BG_PID=$!
  SEE_PIDS="$SEE_PIDS $SEE_BG_PID"
}

# wait_port PORT [SECONDS] : wait until something listens on 127.0.0.1:PORT.
wait_port() {
  local port="$1" deadline=$((SECONDS + ${2:-10}))
  until nc -z 127.0.0.1 "$port" 2>/dev/null; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "see: nothing listening on :$port after ${2:-10}s" >&2
      exit 1
    fi
    sleep 0.1
  done
}

# expect_match [REGEX] : pass if any logged line matches REGEX (default $EXPECT).
expect_match() {
  local regex="${1:-${EXPECT:-}}" line
  if [ -z "$regex" ]; then
    echo "see: no EXPECT= regex declared at the top of see.sh" >&2
    exit 2
  fi
  if line="$(grep -E -m 1 -- "$regex" "$SEE_LOG")"; then
    echo "see: OK, matched /$regex/: $line"
    return 0
  fi
  echo "see: FAIL, no output line matched /$regex/" >&2
  exit 1
}
