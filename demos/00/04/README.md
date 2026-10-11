# Demo 0.4: neveraccept

Lesson: [Kernel Stack and Buffers](../../../docs/00-how-bytes-move/04-KERNEL-STACK-AND-BUFFERS.md)

A server that calls `listen(4)` on `127.0.0.1:9004` and never calls `accept()`, plus eight non-blocking clients in the same process. The kernel completes handshakes on its own and parks each finished connection in the listener's accept queue. Linux lets that queue hold `backlog + 1` connections; after that it drops new SYNs, and the remaining clients stay in `SYN_SENT`, retransmitting. With `--drain` the server finally accepts everything, closing each connection first so that its side lands in `TIME_WAIT`.

```text
neveraccept: listening on 127.0.0.1:9004, backlog 4; accept() is not called
client 1: connected from port 58270 (waiting in the accept queue)
...
client 6: pending from port 58314 (SYN_SENT: no SYN-ACK yet)
result: 5 connected, 3 pending; the accept queue holds backlog+1 = 5
drain: accept() -> fd 12 from port 58332 at +0.6 s
drain: accepted 8; closed first, so they sit in TIME_WAIT (60 s)
```

## Run

```bash
just demo 00/04 python                       # hold 30 s: run ss -lnt in another lab shell
just demo 00/04 python --hold 5 --drain      # then accept and close everything
just demo 00/04 all --smoke                  # 5 queued, 3 pending, all 8 drained
just see 00/04                               # the lesson's See It
```

The `backlog + 1` rule is Linux's (`sk_acceptq_is_full()` in `include/net/sock.h`), so on macOS `run.sh` re-runs itself in the lab.

| Flag | Default | Meaning |
|------|---------|---------|
| `--port N` | `9004` | Port to listen on |
| `--backlog N` | `4` | The `listen()` backlog (capped by `net.core.somaxconn`) |
| `--clients N` | `8` | Non-blocking `connect()` calls to make |
| `--hold S` | `30` | Seconds to wait before draining or exiting |
| `--drain` | off | Accept for up to 4 s, closing each connection server-side first |
| `--smoke` | off | Backlog 4, 8 clients, no hold, drain; passes on 5 connected and 8 drained |

## What to look for

- **`ss -lnt` shows `Recv-Q 5`, `Send-Q 4`.** On a listening socket, Recv-Q is the accept queue's depth and Send-Q its limit.
- **The pending clients' SYNs repeat** in `tcpdump` with the same sequence number: the kernel dropped them and `TcpExtListenOverflows` counted each drop.
- **After `--drain`, `ss -tano state time-wait`** shows the server-side sockets with `timer:(timewait,59sec,0)`.

## Files

| File | Role |
|------|------|
| `python/main.py` | Listener + clients (Python, stdlib) |
| `go/main.go` | neveraccept in Go on the `syscall` package, with an explicit `listen(fd, backlog)` (`net.Listen` would use `somaxconn`); Linux-only |
| `go/main_other.go` | Non-Linux stub (`//go:build !linux`), so `go build` and `go vet` work on macOS; it prints the Linux-only message and exits 2 |
| `go/go.mod` | Makes `go/` a module of its own, so `go build .` honours the build tags |
| `rust/main.rs` | neveraccept in Rust through `libc` (`listen`, non-blocking `connect`, `poll`, `accept`) |
| `rust/Cargo.toml`, `rust/Cargo.lock` | Standalone package `demo-00-04`; one dependency, `libc` |
| `run.sh` | `run.sh LANG [--smoke] [ARGS...]`; re-runs in the lab on macOS |
| `see.sh` | The lesson's See It: `ss -lnt`, SYN retransmits in `tcpdump`, `/proc/net/tcp`, `nstat`, half-open handshakes via an iptables rule, `TIME_WAIT` timers |
