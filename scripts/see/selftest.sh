#!/usr/bin/env bash
# scripts/see/selftest.sh: check that common.sh's process helpers leave no survivors.
#
#   just lab bash scripts/see/selftest.sh
#
# Each case starts a process group with start_bg, ends it with one helper, and fails if
# any live process is left in that group. Exit 0 when every case passes.
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"

failed=0
survivors() { # survivors PGID : live (non-zombie) processes still in the group
  local p out=""
  for p in $(pgrep -g "$1"); do
    if [ -r "/proc/$p/status" ] && ! grep -q '^State:[[:space:]]*Z' "/proc/$p/status"; then out="$out $p"; fi
  done
  echo "$out"
}
check() { # check NAME PGID
  local left
  left="$(survivors "$2")"
  if [ -n "$left" ]; then
    echo "FAIL: $1: group $2 still has$left"
    failed=1
  else
    echo "ok: $1"
  fi
}

start_bg bash -c 'sleep 300 & exit 0' # the parent exits at once; its child sleeps on
group=$SEE_BG_PID
sleep 0.5
wait_bg "$group" 5 || true
check "wait_bg stops the child a finished parent left behind" "$group"

start_bg bash -c 'sleep 300 & sleep 300'
group=$SEE_BG_PID
sleep 0.5
stop_bg "$group" 2
check "stop_bg stops a running parent and its child" "$group"

start_bg bash -c 'trap "" TERM; sleep 300 & wait' # TERM is ignored (and inherited)
group=$SEE_BG_PID
sleep 0.5
stop_bg "$group" 1
check "stop_bg falls back to KILL when TERM is ignored" "$group"

# see_cleanup runs from the EXIT trap of a see.sh that ends with groups still registered.
group="$(bash -c "source '$here/common.sh'; start_bg bash -c 'sleep 300 & exit 0' >/dev/null; echo \$SEE_BG_PID; sleep 0.5")"
sleep 0.2
check "see_cleanup stops groups still registered at exit" "$group"

if [ -n "$SUDO" ] && $SUDO true 2>/dev/null; then
  # shellcheck disable=SC2086  # $SUDO is "sudo -n": two words on purpose
  start_bg $SUDO bash -c 'sleep 300 & exit 0' # root-owned, signalled through $SUDO
  group=$SEE_BG_PID
  sleep 0.5
  wait_bg "$group" 5 || true
  check "wait_bg stops a root-owned child started via \$SUDO" "$group"
fi

[ "$failed" = 0 ] && echo "selftest: OK" || echo "selftest: FAIL"
exit "$failed"
