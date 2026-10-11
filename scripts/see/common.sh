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
# Runs as root in the lab (`just see`) and via passwordless sudo on the CI runner.

set -euo pipefail

# shellcheck disable=SC2034  # SEE_ROOT and SUDO are for the sourcing see.sh
SEE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEE_LOG="$(mktemp "${TMPDIR:-/tmp}/see.XXXXXX")"
SEE_PIDS=""
# Root in the lab; passwordless sudo on the CI runner (-n: fail instead of prompting).
# shellcheck disable=SC2034
if [ "$(id -u)" = 0 ]; then SUDO=""; else SUDO="sudo -n"; fi

SEE_BG_PID=""

# see_alive PID : true while PID is running (a reaped or zombie process counts as gone).
see_alive() {
  [ -r "/proc/$1/status" ] && ! grep -q '^State:[[:space:]]*Z' "/proc/$1/status" 2>/dev/null
}

# see_group_alive PGID : true while any live process is still in process group PGID.
see_group_alive() {
  local p
  for p in $(pgrep -g "$1" 2>/dev/null); do see_alive "$p" && return 0; done
  return 1
}

# see_running PGID : the start_bg process or anything left in its group is still alive.
see_running() { see_alive "$1" || see_group_alive "$1"; }

# see_signal SIG PGID : signal the whole group, as root when the job runs under $SUDO.
see_signal() {
  # shellcheck disable=SC2086  # $SUDO is empty or "sudo -n"
  $SUDO kill -"$1" -- "-$2" 2>/dev/null && return 0
  # No such group (setsid missing): signal the process itself, but only while it is
  # still ours to signal; a reaped pid may already belong to someone else.
  if see_alive "$2"; then $SUDO kill -"$1" "$2" 2>/dev/null || true; fi
}

# see_forget PID : drop a pid from SEE_PIDS once its group is empty, so cleanup never
# signals a reused pid.
see_forget() {
  local p kept=""
  for p in $SEE_PIDS; do [ "$p" = "$1" ] || kept="$kept $p"; done
  SEE_PIDS="$kept"
}

# stop_bg PGID [SECONDS] : TERM the start_bg process's whole group (strace and its tracee,
# a bash -c pipeline, a $SUDO job), wait at most SECONDS (default 3) for the group to
# empty, then KILL it and wait up to 2 s more; reap the parent and forget the group.
stop_bg() {
  local pid="$1" deadline=$((SECONDS + ${2:-3}))
  see_signal TERM "$pid"
  while see_running "$pid" && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.1; done
  if see_running "$pid"; then
    see_signal KILL "$pid"
    deadline=$((SECONDS + 2))
    while see_running "$pid" && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.1; done
  fi
  see_alive "$pid" || { wait "$pid"; } 2>/dev/null || true # reap; never wait on a live pid
  see_forget "$pid"
}

# wait_bg PGID [SECONDS] : wait at most SECONDS (default 10) for a start_bg process to
# exit by itself; then stop anything it left running in its group. Returns 0 if it
# exited in time, 1 if it had to be stopped.
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
  # The parent is gone; anything still in its group (a tracee, a pipeline stage) goes too.
  if see_group_alive "$pid"; then stop_bg "$pid" 2; else see_forget "$pid"; fi
}

# Every start_bg group is stopped (bounded, never an open-ended wait) on any exit path.
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
