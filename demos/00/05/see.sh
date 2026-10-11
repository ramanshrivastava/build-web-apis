#!/usr/bin/env bash
# demos/00/05/see.sh: the syscall boundary of a blocking server and of an epoll server.
#
#   just see 00/05
#
# 1. blocking echo under strace -tt: client B's connection waits in the accept
#    queue (ss -tan: LISTEN Recv-Q 1, and B's connection already ESTAB) until A hangs up
# 2. epoll echo under strace: O_NONBLOCK (CPython sets it with ioctl FIONBIO),
#    epoll_ctl, epoll_wait (epoll_pwait on arm64), and read() = -1 EAGAIN as the
#    "come back later" signal
# 3. /proc/<pid>/fd and lsof: sockets and the eventpoll instance are just fds
# 4. ulimit -n 8: accept() fails with EMFILE and connections pile up in the queue
#
# Every server, tracer and client starts with start_bg, so cleanup stops all of them.
EXPECT='read\(.*= -1 EAGAIN'
source "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/see/common.sh"
require_tool strace ss lsof nc python3

demo="$SEE_ROOT/demos/00/05/python/main.py"
cap="$(mktemp)"
cleanup() { rm -f "$cap"; see_cleanup; }
trap cleanup EXIT
see_sh() { see_log "\$ $1"; see_log "$(bash -c "$1" 2>&1)"; }
# Wait for the listener without connecting to it (a probe would count as a client).
wait_listen() {
  local deadline=$((SECONDS + 10))
  until ss -lnt 'sport = :9005' | grep -q LISTEN; do
    if [ "$SECONDS" -ge "$deadline" ]; then echo "see: nothing listening on :9005" >&2; exit 1; fi
    sleep 0.1
  done
}
# Two clients: A keeps its connection open for 1 s, B arrives 0.2 s after A and
# keeps its own open for B_HOLD seconds (0: hang up right after sending).
clients() {
  start_bg bash -c "(printf 'hello from A\n'; sleep 1) | nc -N 127.0.0.1 9005 >/dev/null"
  sleep 0.2
  start_bg bash -c "(printf 'hello from B\n'; sleep ${B_HOLD:-0}) | nc -N 127.0.0.1 9005 >/dev/null"
  sleep 0.3
}
see_log "# kernel $(uname -r), $(uname -m)"

see_log "## 1. blocking: one client at a time"
start_bg strace -f -tt -e trace=accept4,read,write,close -o "$cap" \
  python3 "$demo" --mode blocking --max-clients 2 >/dev/null
server=$SEE_BG_PID
wait_listen
clients
see_run ss -tan 'sport = :9005'
wait_bg "$server" 10 || true
see_log "\$ strace -f -tt -e trace=accept4,read,write,close python3 $demo --mode blocking --max-clients 2"
see_log "$(sed -n '/accept4/,$p' "$cap" | grep -v -E 'write\(1,|resumed|exited' | head -n 12)"

see_log "## 2. epoll: one thread, every fd non-blocking"
start_bg strace -f -e trace=listen,accept4,read,write,close,ioctl,/^epoll -o "$cap" \
  python3 "$demo" --mode epoll --max-clients 2 >/dev/null
server=$SEE_BG_PID
wait_listen
B_HOLD=0.8 clients
pid="$(pgrep -f -n "$demo --mode epoll")" # the epoll server (strace's child)
see_sh "find /proc/$pid/fd -mindepth 1 -printf '%f -> %l\n' | sort -n"
see_sh "lsof -nP -a -p $pid -d 3-20 | awk '{print \$4, \$5, \$8, \$9}'"
wait_bg "$server" 10 || true
see_log "\$ strace -f -e trace=listen,accept4,read,write,close,ioctl,/^epoll python3 $demo --mode epoll --max-clients 2"
see_log "$(sed -n '/listen(/,$p' "$cap" | grep -v -E 'write\(1,|resumed|exited' | head -n 22)"

see_log "## 3. out of file descriptors: ulimit -n 8"
start_bg bash -c "ulimit -n 8; exec python3 $demo --mode epoll" >"$cap" 2>&1
server=$SEE_BG_PID
wait_listen
for _ in 1 2 3 4 5; do start_bg bash -c "sleep 3 | nc 127.0.0.1 9005 >/dev/null"; done
# Wait until two connections sit in the accept queue (the listener's Recv-Q), then
# long enough for the fourth accept() to fail and fail again after the 1 s back-off.
deadline=$((SECONDS + 10))
until [ "$(ss -lntH 'sport = :9005' | awk '{print $2}')" -ge 2 ]; do
  if [ "$SECONDS" -ge "$deadline" ]; then echo "see: the accept queue never reached 2" >&2; exit 1; fi
  sleep 0.1
done
sleep 1.5
see_run ss -tan 'sport = :9005'
stop_bg "$server"
see_log "\$ bash -c 'ulimit -n 8; exec python3 $demo --mode epoll'"
see_log "$(grep -E 'accept\(\)' "$cap" | tail -n 4)"
expect_match
