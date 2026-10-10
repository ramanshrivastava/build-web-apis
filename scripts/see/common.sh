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
#   wait_port 9000
#   see_run ss -tni 'sport = :9000'     # output is shown AND logged
#   expect_match                        # exit 0 if EXPECT matched, else 1
#
# Runs as root in the lab (`just see`) and via sudo on the CI runner.

set -euo pipefail

# shellcheck disable=SC2034  # SEE_ROOT and SUDO are for the sourcing see.sh
SEE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEE_LOG="$(mktemp "${TMPDIR:-/tmp}/see.XXXXXX")"
SEE_PIDS=""
# shellcheck disable=SC2034
if [ "$(id -u)" = 0 ]; then SUDO=""; else SUDO="sudo"; fi

see_cleanup() {
  local pid
  for pid in $SEE_PIDS; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
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

# start_bg CMD... : start a background process, killed automatically on exit.
start_bg() {
  "$@" &
  SEE_PIDS="$SEE_PIDS $!"
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
