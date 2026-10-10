# Demo 0.6: one echo server, three runtimes

Lesson: [How Runtimes Wrap Syscalls](../../../docs/00-how-bytes-move/06-HOW-RUNTIMES-WRAP-SYSCALLS.md)

Lesson 0.5's epoll echo server, rewritten the way each runtime wants it written: `asyncio.start_server()` in Python, `net.Listen` plus one goroutine per connection in Go, and `tokio::net::TcpListener` plus one task per connection in Rust. None of the three mentions epoll, and all three end up in `epoll_wait()` (`epoll_pwait` on arm64). The See It shows where each runtime keeps its event loop, how many OS threads it uses, and what an idle connection costs.

```text
echo-asyncio: pid 10330, listening on 127.0.0.1:9006 (EpollSelector, 1 thread)
echo-goroutines: pid 13393, listening on 127.0.0.1:9006 (GOMAXPROCS 14, 5 threads)
echo-tokio: pid 13640, listening on 127.0.0.1:9006 (multi-thread runtime, 14 workers)
```

## Run

```bash
just demo 00/06 python            # asyncio on 127.0.0.1:9006 (nc 127.0.0.1 9006 to talk to it)
just demo 00/06 go
just demo 00/06 rust
just demo 00/06 all --smoke       # 50 concurrent clients per language
just see 00/06                    # the lesson's See It
```

All three runtimes are portable (kqueue on macOS, epoll on Linux), so `run.sh` runs natively; the See It needs Linux. The Rust port builds with Cargo (`rust/Cargo.toml`, tokio with only the `rt-multi-thread`, `net`, `io-util` and `macros` features), so its first build downloads crates.

| Flag | Default | Meaning |
|------|---------|---------|
| `--port N` | `9006` | Port to listen on |
| `--buf-size N` | `65536` | Bytes per read; in Go and Rust also the buffer each connection allocates up front (the See It compares 64 KiB with 4 KiB) |
| `--smoke` | off | Start the server in-process, run 50 concurrent clients that each send one line and check the echo, exit 0 if all 50 match |

## What to look for

- **asyncio is one thread** (`Threads: 1`). Its loop is `selectors.EpollSelector.select()` called from `BaseEventLoop._run_once()`, which is exactly where `py-spy dump` finds the idle server.
- **Go reads first and parks second.** `read(4) = -1 EAGAIN`, then the netpoller's `epoll_pwait` returns `EPOLLIN`, then `read(4) = 8`, often on a different OS thread than the first `read()`.
- **tokio names its threads** `tokio-rt-worker`, one per CPU, and whichever worker is idle runs the I/O driver's `epoll_pwait`.
- **Defaults differ underneath:** each runtime picks its own `listen()` backlog (asyncio 100, Go `somaxconn`, tokio 128 in this lab), and an idle connection costs 6–9 KB of RSS in each, except that Go's 64 KiB per-connection buffer becomes resident and dominates (about 59 KB per connection, against 8 KB with `--buf-size 4096`).

## Files

| File | Role |
|------|------|
| `python/main.py` | asyncio echo server and smoke test |
| `go/main.go` | Go echo server: `net.Listen`, a goroutine per connection (stdlib) |
| `rust/main.rs`, `rust/Cargo.toml`, `rust/Cargo.lock` | Rust echo server on tokio |
| `run.sh` | `run.sh LANG [--smoke] [ARGS...]` |
| `see.sh` | The lesson's See It: `strace -f` per runtime, `py-spy dump`, `GODEBUG=schedtrace`, thread names, RSS per idle connection, a GIL probe |

The Go and Rust files here are minimal versions written alongside the lesson so that the See It can trace them; `PORT-SPEC.md` describes what the final ports must print.
