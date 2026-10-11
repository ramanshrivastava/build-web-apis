#!/usr/bin/env bash
# demos/00/06/see.sh: three runtimes, one epoll, and what each one costs.
#
#   just see 00/06
#
# 1. asyncio under strace: one thread; epoll_wait (epoll_pwait on arm64), then
#    accept4, recvfrom and sendto on non-blocking fds
# 2. py-spy dump: the idle event loop is parked in selectors.py's select()
# 3. Go: GODEBUG=schedtrace, the OS threads behind the goroutines, and strace
#    of the netpoller's epoll_pwait + the goroutines' read()/write()
# 4. Rust: tokio's worker threads by name, and strace of the I/O driver
# 5. what an idle connection costs: VmRSS before/after 2000 idle connections
#    (Go with a 64 KiB and a 4 KiB per-connection buffer), and each runtime's
#    default listen() backlog
# 6. the GIL: a thread blocked in recv() lets another thread run; a thread
#    running Python code does not
#
# Every server, tracer and connection holder starts with start_bg, so cleanup
# stops all of them (and strace's tracees) on any exit path.
EXPECT='epoll_p?wait\(.*EPOLLIN.*\) = 1'
source "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/see/common.sh"
require_tool strace ss py-spy nc python3 go cargo

here="$SEE_ROOT/demos/00/06"
cap="$(mktemp)"
godir="$(mktemp -d)"
gobin="$godir/echo-goroutines"
cleanup() { rm -rf "$cap" "$godir"; see_cleanup; }
trap cleanup EXIT
ulimit -n 65536 2>/dev/null || true
wait_listen() {
  local deadline=$((SECONDS + 30))
  until ss -lnt 'sport = :9006' | grep -q LISTEN; do
    if [ "$SECONDS" -ge "$deadline" ]; then echo "see: nothing listening on :9006" >&2; exit 1; fi
    sleep 0.1
  done
}
# Three clients, one after another; each waits 0.2 s before sending, so the
# server's first read() finds nothing and has to park until epoll says "readable".
clients() {
  for n in 1 2 3; do (sleep 0.2; printf 'hello %s\n' "$n") | timeout 5 nc -N 127.0.0.1 9006 >/dev/null; done
}
threads() { # Threads: from /proc, plus a count of thread names
  see_log "\$ grep Threads /proc/$1/status; cat /proc/$1/task/*/comm | sort | uniq -c"
  see_log "$(grep Threads "/proc/$1/status")"
  see_log "$(cat /proc/"$1"/task/*/comm | sort | uniq -c)"
}
# Build the Go and Rust servers first, so compile output stays out of the captures.
go build -o "$gobin" "$here/go/main.go"
cargo build --quiet --release --manifest-path "$here/rust/Cargo.toml"
rustbin="${CARGO_TARGET_DIR:-$here/rust/target}/release/demo-00-06"
see_log "# kernel $(uname -r), $(uname -m); $(python3 -V), $(go version | cut -d' ' -f3), $(rustc -V | cut -d' ' -f1-2)"

see_log "## 1. asyncio under strace"
start_bg strace -f -e 'trace=/^epoll_p?wait$,accept4,recvfrom,sendto' -o "$cap" python3 "$here/python/main.py" >/dev/null
tracer=$SEE_BG_PID
wait_listen
clients
pid="$(pgrep -f -n "$here/python/main.py")"
threads "$pid"
kill "$pid" # the traced server exits, and strace follows it out
wait_bg "$tracer" 5 || true
see_log "\$ strace -f -e 'trace=/^epoll_p?wait\$,accept4,recvfrom,sendto' python3 $here/python/main.py"
see_log "$(sed -n '/accept4/,$p' "$cap" | head -n 12)"

see_log "## 2. py-spy: where the idle loop waits"
start_bg python3 "$here/python/main.py" >/dev/null
pid=$SEE_BG_PID
wait_listen
sleep 0.5
see_run py-spy dump --pid "$pid"
stop_bg "$pid"

see_log "## 3. Go: goroutines on a few threads, one netpoller"
start_bg env GODEBUG=schedtrace=1000 "$gobin" >/dev/null 2>"$cap"
pid=$SEE_BG_PID
wait_listen
clients
sleep 1.2
threads "$pid"
stop_bg "$pid"
see_log "\$ GODEBUG=schedtrace=1000 $gobin"
see_log "$(head -n 2 "$cap")"
start_bg strace -f -e 'trace=/^epoll_p?wait$,accept4,read,write' -o "$cap" "$gobin" >/dev/null
tracer=$SEE_BG_PID
wait_listen
clients
sleep 0.3
pkill -f -n "^$gobin" || true # the traced server exits, and strace follows it out
wait_bg "$tracer" 5 || true
see_log "\$ strace -f -e 'trace=/^epoll_p?wait\$,accept4,read,write' $gobin"
see_log "$(sed -n '/accept4(3/,$p' "$cap" | grep -v -E 'write\(1,|exited|killed' | head -n 14)"

see_log "## 4. Rust: tokio worker threads and the I/O driver"
start_bg "$rustbin" >/dev/null
pid=$SEE_BG_PID
wait_listen
threads "$pid"
stop_bg "$pid"
start_bg strace -f -e 'trace=/^epoll_p?wait$,accept4,recvfrom,sendto' -o "$cap" "$rustbin" >/dev/null
tracer=$SEE_BG_PID
wait_listen
clients
sleep 0.3
pkill -f -n "^$rustbin" || true # the traced server exits, and strace follows it out
wait_bg "$tracer" 5 || true
see_log "\$ strace -f -e 'trace=/^epoll_p?wait\$,accept4,recvfrom,sendto' $rustbin"
see_log "$(sed -n '/accept4(6/,$p' "$cap" | grep -v -E 'write\(1,|exited|killed' | head -n 12)"

see_log "## 5. the cost of 2000 idle connections, and each runtime's listen() backlog"
# Go runs twice: with the default 64 KiB per-connection buffer and with 4 KiB,
# which separates the goroutine's own cost from the buffer it is handed.
established() { ss -tnH state established '( sport = :9006 )' | wc -l; }
for run in python go go-4k rust; do
  case "$run" in
    python) start_bg python3 "$here/python/main.py" >/dev/null ;;
    go) start_bg "$gobin" >/dev/null ;;
    go-4k) start_bg "$gobin" --buf-size 4096 >/dev/null ;;
    rust) start_bg "$rustbin" >/dev/null ;;
  esac
  pid=$SEE_BG_PID
  wait_listen
  sleep 0.5
  backlog="$(ss -lntH 'sport = :9006' | awk '{print $3}')"
  before="$(awk '/VmRSS/ {print $2}' "/proc/$pid/status")"
  # 2000 connections, paced so the smallest accept queue (asyncio's 100) never
  # overflows, held open until the server has been sampled and stopped.
  start_bg python3 -c '
import socket, time
conns = []
for i in range(2000):
    conns.append(socket.create_connection(("127.0.0.1", 9006)))
    if i % 50 == 0:
        time.sleep(0.01)
time.sleep(120)'
  holder=$SEE_BG_PID
  deadline=$((SECONDS + 30))
  until [ "$(established)" -ge 2000 ] || [ "$SECONDS" -ge "$deadline" ] || ! see_alive "$holder"; do
    sleep 0.2
  done
  sleep 4 # let the allocators settle before sampling VmRSS
  count="$(established)"
  if [ "$count" -lt 2000 ] || ! see_alive "$holder"; then
    echo "see: the $run server has $count of 2000 idle connections (holder alive: $(see_alive "$holder" && echo yes || echo no))" >&2
    exit 1
  fi
  after="$(awk '/VmRSS/ {print $2}' "/proc/$pid/status")"
  nthreads="$(awk '/Threads/ {print $2}' "/proc/$pid/status")"
  see_log "$run: listen backlog $backlog; $count idle connections: VmRSS $before -> $after kB" \
    "(+$(((after - before) * 1024 / count)) bytes each), $nthreads threads"
  stop_bg "$pid"
  stop_bg "$holder"
  sleep 0.5
done

see_log "## 6. the GIL is released around blocking socket calls"
see_log "$(python3 - <<'PY'
import socket, threading, time

def spin(seconds, out):
    n, end = 0, time.monotonic() + seconds
    while time.monotonic() < end:
        n += 1
    out.append(n)

a, b = socket.socketpair()
blocked = []
t = threading.Thread(target=spin, args=(1.0, blocked))
t.start()
threading.Timer(1.0, b.send, (b"x",)).start()
a.recv(1)  # main thread blocks in recvfrom() for 1 s, without the GIL
t.join()
busy = []
t = threading.Thread(target=spin, args=(1.0, busy))
t.start()
end = time.monotonic() + 1.0
while time.monotonic() < end:
    pass  # main thread runs Python bytecode for 1 s, holding the GIL
t.join()
print(f"spin thread, main blocked in recv():  {blocked[0]:>10} iterations")
print(f"spin thread, main running Python:     {busy[0]:>10} iterations")
PY
)"
expect_match
