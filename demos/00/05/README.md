# Demo 0.5: blocking echo vs raw epoll echo

Lesson: [Socket Syscalls](../../../docs/00-how-bytes-move/05-SOCKET-SYSCALLS.md)

One echo server on `127.0.0.1:9005`, written two ways. Every line it prints names the syscall it just made, so its output lines up with `strace`.

- `--mode blocking`: `socket()`, `bind()`, `listen()`, then `accept()` and `read()`/`write()` for one client at a time. While the server sits in `read()` on client A, client B's finished connection waits in the accept queue.
- `--mode epoll`: every fd is `O_NONBLOCK`, one `epoll` instance reports which fds are ready, and `read()` returning `EAGAIN` means "drained, go back to `epoll_wait()`". One thread serves every client.

```text
echo-epoll: pid 83438, listening fd 3 on 9005, epoll fd 4
epoll_wait() = 1 ready: fd 3
accept() = fd 5 from port 62192, O_NONBLOCK, added to epoll
accept() = EAGAIN (accept queue empty)
epoll_wait() = 1 ready: fd 5
read(5) = 13
write(5) = 13
read(5) = EAGAIN (drained; back to epoll_wait)
```

## Run

```bash
just demo 00/05 python --mode blocking        # then, in a second lab shell: nc 127.0.0.1 9005
just demo 00/05 python --mode epoll
just demo 00/05 all --smoke                   # both modes, two clients each
just see 00/05                                # the lesson's See It
```

`epoll` is Linux-only, so on macOS `run.sh` re-runs itself in the lab.

| Flag | Default | Meaning |
|------|---------|---------|
| `--mode M` | `epoll` | `blocking` or `epoll` |
| `--port N` | `9005` | Port to listen on |
| `--max-clients N` | `0` | Exit after N clients have hung up (0: run forever) |
| `--smoke` | off | Runs both modes with two clients: in blocking mode B is echoed only after A hangs up, in epoll mode B is echoed while A is still connected |

## What to look for

- **Blocking mode:** `ss -tan` shows the listener's `Recv-Q 1` while client A is connected: B's connection is complete and waiting (its bytes and even its FIN already received), and `strace -tt` shows its `accept4()` exactly when A's `close()` returns.
- **Epoll mode:** `read(5, …) = -1 EAGAIN` after every drain. That is how a non-blocking socket says "nothing more now".
- **On arm64, `epoll_wait()` is `epoll_pwait` in strace**, because arm64 has no `epoll_wait` syscall; libc implements one with the other.
- **Short writes:** `write()` may take only part of what it is given. Blocking mode loops until every byte is back; epoll mode keeps the rest as a per-connection debt, watches `EPOLLOUT`, and prints `write(5) = 49510 (short write: 16026 bytes pending, waiting for EPOLLOUT)` when a client reads slowly.
- **`ulimit -n 8`:** `accept()` fails with `EMFILE`, and the connections it could not take stay in the accept queue.

## Files

| File | Role |
|------|------|
| `python/main.py` | Both servers and the smoke test (Python, stdlib: `select.epoll`, `os.read`, `os.write`) |
| `go/main.go` | Both servers in Go with raw syscalls (`syscall.Accept4`, `syscall.SetNonblock`, `syscall.EpollWait`), not `net.Listen`; Linux-only |
| `go/main_other.go` | Non-Linux stub (`//go:build !linux`), so `go build` and `go vet` work on macOS; it prints the Linux-only message and exits 2 |
| `go/go.mod` | Makes `go/` a module of its own, so `go build .` honours the build tags |
| `rust/main.rs` | Both servers in Rust through `libc` (`accept4`, `fcntl`, `epoll_wait`), not `std::net` or mio |
| `rust/Cargo.toml`, `rust/Cargo.lock` | Standalone package `demo-00-05`; one dependency, `libc` |
| `run.sh` | `run.sh LANG [--smoke] [ARGS...]`; re-runs in the lab on macOS |
| `see.sh` | The lesson's See It: `strace` of both modes, `ss -tan`, `/proc/<pid>/fd`, `lsof`, `ulimit -n` exhaustion |
