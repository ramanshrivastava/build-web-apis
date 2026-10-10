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
# 5. what an idle connection costs: VmRSS before/after 2000 idle connections,
#    and each runtime's default listen() backlog
# 6. the GIL: a thread blocked in recv() lets another thread run; a thread
#    running Python code does not
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
  for n in 1 2 3; do (sleep 0.2; printf 'hello %s\n' "$n") | nc -N 127.0.0.1 9006 >/dev/null; done
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
strace -f -e 'trace=/^epoll_p?wait$,accept4,recvfrom,sendto' -o "$cap" python3 "$here/python/main.py" >/dev/null &
wait_listen
clients
pid="$(pgrep -f -n "$here/python/main.py")"
threads "$pid"
kill "$pid"
sleep 0.3
see_log "\$ strace -f -e 'trace=/^epoll_p?wait\$,accept4,recvfrom,sendto' python3 $here/python/main.py"
see_log "$(sed -n '/accept4/,$p' "$cap" | head -n 12)"

see_log "## 2. py-spy: where the idle loop waits"
python3 "$here/python/main.py" >/dev/null &
pid=$!
wait_listen
sleep 0.5
see_run py-spy dump --pid "$pid"
kill "$pid"
wait "$pid" 2>/dev/null || true

see_log "## 3. Go: goroutines on a few threads, one netpoller"
GODEBUG=schedtrace=1000 "$gobin" >/dev/null 2>"$cap" &
pid=$!
wait_listen
clients
sleep 1.2
threads "$pid"
kill "$pid"
wait "$pid" 2>/dev/null || true
see_log "\$ GODEBUG=schedtrace=1000 $gobin"
see_log "$(head -n 2 "$cap")"
strace -f -e 'trace=/^epoll_p?wait$,accept4,read,write' -o "$cap" "$gobin" >/dev/null &
wait_listen
clients
sleep 0.3
pkill -f -n "^$gobin" || true
sleep 0.3
see_log "\$ strace -f -e 'trace=/^epoll_p?wait\$,accept4,read,write' $gobin"
see_log "$(sed -n '/accept4(3, {/,$p' "$cap" | grep -v -E 'write\(1,|exited|killed' | head -n 14)"

see_log "## 4. Rust: tokio worker threads and the I/O driver"
"$rustbin" >/dev/null &
pid=$!
wait_listen
threads "$pid"
kill "$pid"
wait "$pid" 2>/dev/null || true
strace -f -e 'trace=/^epoll_p?wait$,accept4,recvfrom,sendto' -o "$cap" "$rustbin" >/dev/null &
wait_listen
clients
sleep 0.3
pkill -f -n "^$rustbin" || true
sleep 0.3
see_log "\$ strace -f -e 'trace=/^epoll_p?wait\$,accept4,recvfrom,sendto' $rustbin"
see_log "$(sed -n '/accept4(6, {/,$p' "$cap" | grep -v -E 'write\(1,|exited|killed' | head -n 12)"

see_log "## 5. the cost of 2000 idle connections, and each runtime's listen() backlog"
for lang in python go rust; do
  case "$lang" in
    python) python3 "$here/python/main.py" >/dev/null & ;;
    go) "$gobin" >/dev/null & ;;
    rust) "$rustbin" >/dev/null & ;;
  esac
  pid=$!
  wait_listen
  sleep 0.5
  backlog="$(ss -lntH 'sport = :9006' | awk '{print $3}')"
  before="$(awk '/VmRSS/ {print $2}' "/proc/$pid/status")"
  # 2000 connections, paced so the smallest accept queue (asyncio's 100) never overflows.
  python3 -c '
import socket, time
conns = []
for i in range(2000):
    conns.append(socket.create_connection(("127.0.0.1", 9006)))
    if i % 50 == 0:
        time.sleep(0.01)
time.sleep(30)' &
  holder=$!
  deadline=$((SECONDS + 30))
  until [ "$(ss -tnH state established '( sport = :9006 )' | wc -l)" -ge 2000 ] || [ "$SECONDS" -ge "$deadline" ]; do sleep 0.2; done
  sleep 1
  established="$(ss -tnH state established '( sport = :9006 )' | wc -l)"
  after="$(awk '/VmRSS/ {print $2}' "/proc/$pid/status")"
  nthreads="$(awk '/Threads/ {print $2}' "/proc/$pid/status")"
  see_log "$lang: listen backlog $backlog; $established idle connections: VmRSS $before -> $after kB" \
    "(+$(((after - before) * 1024 / established)) bytes each), $nthreads threads"
  kill "$holder" "$pid" 2>/dev/null || true
  wait "$holder" "$pid" 2>/dev/null || true
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
