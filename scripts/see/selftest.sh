#!/usr/bin/env bash
# scripts/see/selftest.sh: check that common.sh's process helpers leave no survivors.
#
#   just lab bash scripts/see/selftest.sh
#
# Each case starts a process group with start_bg, ends it with one helper, and fails if
# any live process is left in that group. The whole suite runs under `timeout 60`, so a
# helper that waits forever fails the suite instead of hanging it. Exit 0 when every
# case passes. Run it as root (the lab) and as a user with passwordless sudo (CI): the
# last case, a root-owned group that ignores TERM, runs only in the second setting.
if [ -z "${SEE_SELFTEST_INNER:-}" ]; then
  SEE_SELFTEST_INNER=1 timeout 60 bash "$0" "$@"
  status=$?
  if [ "$status" = 124 ]; then echo "selftest: FAIL, still running after 60 s (an unbounded wait)"; fi
  exit "$status"
fi

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

# A group that survives KILL. A truly unkillable process (stuck in the kernel) cannot be
# made on demand, so simulate signals that never arrive by stubbing see_signal; stop_bg
# must then give up within its deadlines, warn, return 1 and keep the group registered.
start_bg bash -c 'sleep 300 & sleep 300'
group=$SEE_BG_PID
sleep 0.5
eval "orig_$(declare -f see_signal)"
see_signal() { :; }
if stop_bg "$group" 1 2>/dev/null; then status=0; else status=$?; fi
eval "$(declare -f orig_see_signal | sed '1s/^orig_//')"
case " $SEE_PIDS " in *" $group "*) kept=yes ;; *) kept=no ;; esac
if [ "$status" = 1 ] && [ "$kept" = yes ]; then
  echo "ok: stop_bg returns 1 and keeps a group it could not empty"
else
  echo "FAIL: stop_bg on an unkillable group returned $status, kept the record: $kept"
  failed=1
fi
stop_bg "$group" 1 # now with real signals
check "the kept group is stopped on the next attempt" "$group"

# see_cleanup runs from the EXIT trap of a see.sh that ends with groups still registered.
group="$(bash -c "source '$here/common.sh'; start_bg bash -c 'sleep 300 & exit 0' >/dev/null; echo \$SEE_BG_PID; sleep 0.5")"
sleep 0.2
check "see_cleanup stops groups still registered at exit" "$group"

if [ -n "$SUDO" ] && $SUDO true 2>/dev/null; then
  # Root-owned, and its child ignores TERM: only a KILL sent through $SUDO stops it.
  # shellcheck disable=SC2086  # $SUDO is "sudo -n": two words on purpose
  start_bg $SUDO bash -c 'trap "" TERM; sleep 300 & exit 0'
  group=$SEE_BG_PID
  sleep 0.5
  wait_bg "$group" 5 || true
  check "a root-owned child that ignores TERM is KILLed through \$SUDO" "$group"
fi

if [ "$failed" = 0 ]; then echo "selftest: OK"; else echo "selftest: FAIL"; fi
exit "$failed"
