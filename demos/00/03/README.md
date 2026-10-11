# Demo 0.3: slowreader

Lesson: [TCP Flow and Congestion](../../../docs/00-how-bytes-move/03-TCP-FLOW-AND-CONGESTION.md)

One process, two sockets on `127.0.0.1:9003`. A sender thread accepts one connection and calls `send()` with 64 KiB chunks as fast as the kernel takes them. The reader sets a tiny `SO_RCVBUF` *before* `connect()` and reads 1 KiB every 100 ms. Every second the demo prints how many bytes the sender's kernel accepted, how many the reader has read, the difference (bytes sitting in kernel buffers), and how long the sender's current `send()` call has been blocked.

```text
slowreader: sender listening on 127.0.0.1:9003
slowreader: reader SO_RCVBUF asked 4096, kernel set 8192
slowreader: reading 1024 bytes every 0.100 s for 5 s
t=1s sent=1769472 read=11264 in-kernel=1758208 read-rate=10.8 KiB/s send-blocked=1018ms
t=2s sent=1769472 read=21504 in-kernel=1747968 read-rate=10.3 KiB/s send-blocked=2031ms
summary: sent=1769472 read=51200 longest send() block=5063 ms
```

## Run

```bash
just demo 00/03 python                                                   # the slow reader
just demo 00/03 python --rcvbuf 65536 --read-size 65536 --interval 0     # a fast reader, fixed window
just demo 00/03 python --rcvbuf 0 --read-size 65536 --interval 0         # a fast reader, autotuned window
just demo 00/03 all --smoke                                              # 3 s; passes if send() blocked
just see 00/03                                                           # the lesson's See It
```

Plain TCP sockets, so the demo runs natively on macOS too (where `SO_RCVBUF` is not doubled). The See It needs Linux: `tcpdump`, `ss -tni`, `nstat` and `tc netem` run in the lab.

| Flag | Default | Meaning |
|------|---------|---------|
| `--port N` | `9003` | Port the sender listens on |
| `--rcvbuf N` | `4096` | Reader `SO_RCVBUF` in bytes, set before `connect()`; `0` leaves autotuning on |
| `--read-size N` | `1024` | Bytes per `recv()` |
| `--interval S` | `0.1` | Sleep between reads; `0` reads flat out |
| `--seconds S` | `10` | How long the reader runs |
| `--smoke` | off | 3 s with the defaults; passes if a `send()` call blocked for 200 ms or more |

## What to look for

- **`send-blocked` keeps growing.** The sender is parked inside `send()` because its send buffer is full, and the send buffer is full because the reader advertised a zero window.
- **`in-kernel` is close to the sender's `Send-Q` plus the reader's `Recv-Q`** in `ss -tn`, but only an estimate: it counts completed `send()` calls only, and a segment received but not yet acknowledged sits in both queues at once. Either way the bytes are not lost; they wait in kernel buffers.
- **With netem delay, a fixed 64 KiB buffer caps throughput** at about window ÷ RTT, however fast the link is. That is the bandwidth-delay product.

## Files

| File | Role |
|------|------|
| `python/main.py` | Sender thread + slow reader (Python, stdlib) |
| `go/main.go` | slowreader in Go: `SO_RCVBUF` set in `net.Dialer.Control` before `connect()` (stdlib) |
| `rust/main.rs` | slowreader in Rust: the reader socket built with `libc` (`socket`, `setsockopt`, `connect`), then wrapped in a `TcpStream` |
| `rust/Cargo.toml`, `rust/Cargo.lock` | Standalone package `demo-00-03`; one dependency, `libc` |
| `run.sh` | `run.sh LANG [--smoke] [ARGS...]` |
| `see.sh` | The lesson's See It: `tcpdump` (`win 0`), `ss -tni`, `nstat`, `tc netem` delay and loss on port 9003 |
