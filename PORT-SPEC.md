# PORT-SPEC: Module 0, How Bytes Move

The contract for the Go and Rust ports of Module 0's six demos. Read this file and `demos/00/LL/python/main.py`; nothing else is needed. The Python demo is the reference: when this spec and the Python code disagree on an output line, the Python code wins and this spec is a bug.

Module 0 has **no app code**: `apps/` stays untouched (CLAUDE.md gate M0). Ports live only in `demos/00/LL/go/` and `demos/00/LL/rust/`.

## What the Porter owns

| Path | Owner |
|------|-------|
| `demos/00/LL/go/**`, `demos/00/LL/rust/**` | Porter |
| The `## N. Code: Go` and `## N. Code: Rust` sections of `docs/00-how-bytes-move/LL-*.md` | Porter (edit by heading; replace the `<!-- PORTER: fill from … -->` comment) |
| New rows in each lesson's `## Key Files Summary` for the Go and Rust files you add | Porter (the rows must point at files that exist) |
| Everything else: prose, Mermaid, `Code: Python`, See It, `run.sh`, `see.sh`, `README.md` in each demo, this file | Author. Ask the Author for any change |

## Layout and build rules (how `run.sh` finds your port)

Every `run.sh` already handles Go and Rust; nothing in it needs to change.

| Language | Files | How `run.sh` builds it |
|----------|-------|------------------------|
| Go | `go/main.go`, `package main`. Optional `go/go.mod` only if you need a module dependency (none should be needed). | With `go.mod`: `cd go && go build -o BIN .`; without: `go build -o BIN go/main.go` |
| Rust, std only | `rust/main.rs` | `rustc --edition 2021 -O rust/main.rs -o BIN` |
| Rust with crates | `rust/main.rs` + `rust/Cargo.toml` (+ commit `rust/Cargo.lock`) | `cargo build --quiet --release --manifest-path rust/Cargo.toml`, then runs `${CARGO_TARGET_DIR:-rust/target}/release/demo-00-LL` |

Rules:

- **Binary name:** the Cargo `[[bin]]` must be named `demo-00-LL` with `path = "main.rs"`, and the manifest must contain an empty `[workspace]` table so it never joins another workspace. See `demos/00/06/rust/Cargo.toml` for the exact shape.
- **Dependencies:** Go: stdlib only (`syscall` is fine; `golang.org/x/sys/unix` is not needed). Rust: std, plus the `libc` crate where a syscall has no std wrapper (0.1, 0.3, 0.4, 0.5), plus `tokio` for 0.6 only. Use the smallest feature set (`default-features = false` where it builds).
- **Same CLI:** the same flags with the same defaults, parsed by hand or with `flag` (Go) / `std::env::args` (Rust); no `clap`. `--smoke` must exit 0 on success and non-zero on failure within 60 s, including build time on a cold cache.
- **Same output lines:** every line listed below, character for character except the values that vary per run (PIDs, ports, fds, byte counts, timestamps, ids). `see.sh` and the lessons quote these lines.
- **Same exit codes:** listed per demo.
- **Platform:** 0.1, 0.4 and 0.5 are Linux-only (`run.sh` re-runs itself in the lab on macOS). Guard Linux-only code so `go vet`/`cargo check` still work on macOS (Go: `//go:build linux` plus a stub file that prints the Linux-only message and exits 2 is fine; Rust: `#[cfg(target_os = "linux")]`). 0.2, 0.3 and 0.6 must also run natively on macOS.
- **Style:** `gofmt`, `go vet` clean; `cargo fmt`, `cargo clippy -- -D warnings` clean (or `rustc` without warnings for single-file ports). Comments explain *why* the mechanism works, like the Python file.
- **Verify:** `just demo 00/LL go --smoke`, `just demo 00/LL rust --smoke`, then `just demo-smoke`. On macOS the Linux-only demos run in the lab automatically.

## The lesson sections

Each `Code: Go` / `Code: Rust` section currently holds one paragraph saying what the port must show, then `<!-- PORTER: fill from demos/00/LL/go/main.go -->` (or `rust/main.rs`), then a `TICKETING EXAMPLE:` fence. Replace the comment with: a short explanation of only what differs from Python (the runtime, the types, the error handling), one or two excerpts under about 40 lines that match your file exactly, and keep (or improve) the existing paragraph and the ticketing fence. Then add your files to `## Key Files Summary`:

```markdown
| `demos/00/LL/go/main.go` | <role> | Go |
| `demos/00/LL/rust/main.rs` | <role> | Rust |
```

Run `just lint-docs` afterwards: the linter fails on a Key Files path that does not exist or a heading out of order.

---

## 0.1 `demos/00/01`: AF_PACKET sniffer

**Flags:** `--iface IFACE` (default `lo`), `-n N` / `--count N` (default 10), `--timeout S` (float, default 10), `--smoke`.

**Behaviour:** open `socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL))`, bind it to one interface (`sockaddr_ll` with `sll_protocol = htons(ETH_P_ALL)` and `sll_ifindex = if_nametoindex(iface)`), then `recvfrom()` frames until `count` frames or `timeout` seconds. Use a receive timeout (`SO_RCVTIMEO` 0.5 s, or `poll`) so the deadline is honoured. For each frame, parse the 14-byte Ethernet header and, for EtherType 0x0800, the IPv4 header (IHL, protocol, addresses) and the UDP/TCP ports. The direction comes from `sll_pkttype` in the address `recvfrom()` returns.

**Smoke:** always on `lo`, count 50, timeout 5 s. Bind a UDP receiver on `127.0.0.1:9001` *after* opening the packet socket, send three datagrams with payload `m0 smoke` to it from another UDP socket, then read frames until one IPv4 frame to dport 9001 has been seen with pkttype `outgoing` *and* one with `host`.

**Output lines:**

```text
sniff: AF_PACKET socket fd=3 bound to lo (ifindex 1)
frame 1: 00:00:00:00:00:00 > 00:00:00:00:00:00 type 0x0800 IPv4 len 50 outgoing | UDP 127.0.0.1:59186 > 127.0.0.1:9001
frame 2: 00:00:00:00:00:00 > 00:00:00:00:00:00 type 0x0800 IPv4 len 50 host | UDP 127.0.0.1:59186 > 127.0.0.1:9001
smoke: OK, the datagram to :9001 crossed lo twice (outgoing, host)
```

- Frame line: `frame {n}: {src mac} > {dst mac} type 0x{ethertype:04x} {name} len {frame bytes} {pkttype}` then, for IPv4 only, ` | {PROTO} {src}:{sport} > {dst}:{dport}` (TCP/UDP) or ` | {PROTO} {src} > {dst}` (anything else). MACs lowercase, colon-separated. Names: `0x0800 IPv4`, `0x0806 ARP`, `0x86dd IPv6`, `0x8100 802.1Q`, anything else `?`. PROTO: `ICMP`, `TCP`, `UDP`, else `proto {n}`. Pkttype: `0 host`, `1 broadcast`, `2 multicast`, `3 otherhost`, `4 outgoing`, else the number. An IPv4 payload under 20 bytes prints ` | short IPv4 header`; a version other than 4, an IHL under 20 bytes or an IHL longer than the payload prints ` | malformed IPv4 header`; a fragment with a non-zero offset (bytes 6–7, low 13 bits, times 8) prints ` | {PROTO} {src} > {dst} fragment at byte {offset}` and never decodes ports, because its payload starts mid-datagram.
- Failure: `smoke: FAIL, saw {sorted set or 'no'} copies of the datagram to :9001` (Python prints the sorted list, e.g. `['host']`; Go/Rust may print `[host]`).
- Errors: no AF_PACKET (non-Linux) `sniff: AF_PACKET is Linux-only; run it in the lab: just demo 00/01 python` exit 2 (say `go`/`rust` instead of `python`); EPERM `sniff: AF_PACKET needs CAP_NET_RAW; run as root (the lab runs as root)` exit 3; bind failure `sniff: cannot bind to '{iface}': {strerror}` exit 2.

**Exit codes:** 0 ok, 1 smoke failed, 2 platform/usage/bind error, 3 permission.

**Must reproduce:** Go: `syscall.Socket(syscall.AF_PACKET, syscall.SOCK_RAW, int(htons(syscall.ETH_P_ALL)))`, `syscall.Bind` with `*syscall.SockaddrLinklayer`, `syscall.Recvfrom` returning `*syscall.SockaddrLinklayer` (read `Pkttype`); not `gopacket`, not pcap. Rust: `libc::socket(AF_PACKET, SOCK_RAW, (ETH_P_ALL as u16).to_be() as i32)`, `libc::bind` with `libc::sockaddr_ll`, `libc::recvfrom` into a `sockaddr_ll` (read `sll_pkttype`), via the `libc` crate. The point of the lesson is that the frame arrives *with* its link-layer header and that `lo` delivers each frame twice (once from `dev_queue_xmit_nit()`, once on receive).

## 0.2 `demos/00/02`: DNS query by hand

**Flags:** positional `NAME` (default `example.com`), `--type T` (one of `A AAAA CNAME NS SOA TXT`, default `A`), `--server IP` (default: first IPv4 `nameserver` in `/etc/resolv.conf`), `--port N` (default 53), `--tcp`, `--smoke`.

**Behaviour:** build the query by hand (no resolver library, no `net.Resolver`, no `trust-dns`/`hickory`): 12-byte header `id` (random 16 bits), flags `0x0100` (RD), qdcount 1, others 0; the name as length-prefixed labels ending in `00`; qtype; class IN (1). Print it as a hex dump, send it with one `sendto()`/`WriteTo` on a UDP socket (3 s timeout), read one reply with `recvfrom()` into a 4096-byte buffer, parse the header and refuse the reply unless its id matches (one `checked_reply`/`checkedReply` path that every answer goes through, the TCP fallback's included), skip the question, parse answers with name-compression pointers (`0xC0` prefix; guard against loops after 20 jumps). If `tc=1` and not `--tcp`, print the `truncated:` line and repeat the same query over TCP: prefix the 2-byte big-endian length, `sendall`, read until `2 + length` bytes have arrived.

**Smoke:** `example.com A` over UDP, then over TCP; pass if both rcodes are NOERROR and at least one `A` answer arrived. `run.sh` skips the smoke when `CI_OFFLINE=1`; the binary itself does not need to check.

**Output lines** (order as below; the query block repeats for each resolve):

```text
dns: resolver 192.168.65.7:53
query: example.com A id=0x47cf, 29 bytes
  0000  47 cf 01 00 00 01 00 00 00 00 00 00 07 65 78 61  G............exa
  0010  6d 70 6c 65 03 63 6f 6d 00 00 01 00 01           mple.com.....
sendto() 29 bytes -> 192.168.65.7:53 (UDP)
recvfrom() 83 bytes <- 192.168.65.7:53
header: id=0x47cf qr=1 tc=0 rd=1 ra=1 rcode=NOERROR questions=1 answers=2
answer: example.com A 172.66.147.243 ttl=377
truncated: the answer did not fit in 512 bytes of UDP; retrying over TCP
send() 30 bytes -> 192.168.65.7:53 (TCP, 2-byte length + query)
recv() 1348 bytes <- 192.168.65.7:53 (length prefix says 1346)
smoke: OK, example.com resolved over UDP and TCP (4 A records)
```

- Hex dump: two spaces, 4-digit lowercase hex offset, two spaces, up to 16 bytes as `%02x` separated by single spaces padded to 47 characters, two spaces, ASCII with non-printables (outside 32..126) as `.`.
- Answer line: `answer: {name} {TYPE} {value} ttl={ttl}`; name without the trailing dot (`.` for the root); TYPE from the table or the number; value: A/AAAA as addresses, NS/CNAME as names, TXT as the strings joined by a space in double quotes truncated to 60 characters plus `...`, anything else `({rdlength} bytes)`.
- rcode names: `0 NOERROR`, `1 FORMERR`, `2 SERVFAIL`, `3 NXDOMAIN`, `4 NOTIMP`, `5 REFUSED`, else the number.
- Errors: no nameserver `dns: no IPv4 nameserver in /etc/resolv.conf; pass --server IP` exit 2; any socket/parse error `dns: FAIL, {error}` exit 1; smoke without an A record `smoke: FAIL, no A record for example.com` exit 1.

**Exit codes:** 0 ok, 1 failure, 2 no resolver.

**Must reproduce:** one UDP datagram out, one in (the See It's strace shows `sendto(…) = 28`, `recvfrom(…) = 495`), then a TCP connection with the length prefix. Go: `net.ListenPacket("udp4", ":0")` + `WriteTo`/`ReadFrom` (or `DialUDP`), `encoding/binary.BigEndian`, `net.DialTimeout("tcp", …)`; Rust: `std::net::UdpSocket::send_to`/`recv_from`, `TcpStream::connect_timeout`, `u16::to_be_bytes`. std/stdlib only.

## 0.3 `demos/00/03`: slowreader

**Flags:** `--port N` (default 9003), `--rcvbuf N` (default 4096; `0` = do not set, leave autotuning on), `--read-size N` (default 1024), `--interval S` (float, default 0.1; 0 = read flat out), `--seconds S` (float, default 10), `--smoke`.

**Behaviour:** one process. Listener on `127.0.0.1:{port}` with `SO_REUSEADDR`, backlog 1. A sender thread/goroutine/thread accepts one connection and loops: record the time, `send()` a 64 KiB chunk of `x` bytes (blocking), add the accepted byte count to `sent`, update `longest_block`; it exits on any send error (EPIPE/ECONNRESET). The reader creates its socket, sets `SO_RCVBUF` **before** `connect()` when `rcvbuf > 0`, reads it back with `getsockopt`, connects, then loops for `seconds`: `recv(read_size)`, add to `read`, sleep `interval`. Once per second it prints a report line. "send-blocked" is how long the sender's *current* `send()` call has been running (0 if none is in progress). After the loop: fold the in-progress block into `longest_block`, close the reader and listener, print the summary.

**Smoke:** rcvbuf 4096, read 1024, interval 0.1, 3 s; pass if `longest_block >= 0.2 s`.

**Output lines:**

```text
slowreader: sender listening on 127.0.0.1:9003
slowreader: reader SO_RCVBUF asked 4096, kernel set 8192
slowreader: reading 1024 bytes every 0.100 s for 5 s
t=1s sent=1769472 read=11264 in-kernel=1758208 read-rate=10.8 KiB/s send-blocked=1018ms
summary: sent=1769472 read=51200 longest send() block=5063 ms
smoke: OK, the slow reader closed the window and send() blocked
```

- With `--rcvbuf 0`: `slowreader: reader SO_RCVBUF left to autotuning, starts at {getsockopt value}`.
- `reading … every {interval:.3f} s for {seconds formatted like %g} s` (`5`, `3`, `2.5`).
- Report: `t={n}s sent={sent} read={read} in-kernel={sent-read} read-rate={read/elapsed/1024:.1f} KiB/s send-blocked={ms:.0f}ms`, printed when elapsed passes each whole second.
- Failure: `smoke: FAIL, send() never blocked: flow control did not stop the sender` exit 1.

**Exit codes:** 0 ok, 1 smoke failed.

**Must reproduce:** `SO_RCVBUF` set before `connect()` (the window scale goes out in the SYN; the lesson's `ss -tni` shows `wscale:0,10`). Go: `net.Dialer{Control: func(...) { c.Control(func(fd uintptr) { syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_RCVBUF, n) }) }}`; counters via `sync/atomic`. Rust: std cannot set options before `connect`, so create the socket with `libc::socket` + `libc::setsockopt(SO_RCVBUF)` + `libc::connect` and wrap it with `TcpStream::from_raw_fd` (or use `socket2`, but prefer `libc` for consistency with 0.1/0.4/0.5); counters in `AtomicU64`/`Arc`. The sender must use plain blocking writes (`conn.Write` in Go is fine: it parks the goroutine exactly where Python's `send()` blocks).

## 0.4 `demos/00/04`: neveraccept

**Flags:** `--port N` (default 9004), `--backlog N` (default 4), `--clients N` (default 8), `--hold S` (float, default 30), `--drain`, `--smoke`.

**Behaviour:** listener on `127.0.0.1:{port}` with `SO_REUSEADDR`, `listen(fd, backlog)` with **exactly** that backlog. Never call `accept()` until the drain. Start `clients` non-blocking `connect()`s (each returns 0 or `EINPROGRESS`; anything else is an error), sleep 0.5 s, then classify each client: connected if `poll(POLLOUT, 0)` reports writable and `SO_ERROR == 0`, else pending. If `hold > 0`, print the hold line and sleep. With `--drain`: make the listener non-blocking and for up to 4 s accept until `clients` connections were taken, sleeping 50 ms on `EAGAIN`; print one line per accept and close each accepted socket immediately (server closes first, so the server side lands in `TIME_WAIT`). Then close all clients and the listener.

**Smoke:** backlog 4, 8 clients, hold 0, drain; pass if exactly 5 connected and 8 drained.

**Output lines:**

```text
neveraccept: listening on 127.0.0.1:9004, backlog 4; accept() is not called
client 1: connected from port 58270 (waiting in the accept queue)
client 6: pending from port 58314 (SYN_SENT: no SYN-ACK yet)
result: 5 connected, 3 pending; the accept queue holds backlog+1 = 5
holding 30 s: try  ss -lnt 'sport = :9004'
drain: accept() -> fd 12 from port 58332 at +0.6 s
drain: accepted 8; closed first, so they sit in TIME_WAIT (60 s)
smoke: OK, 5 waited in the accept queue, 3 were dropped, all 8 drained
```

- `holding {hold formatted like %g} s: try  ss -lnt 'sport = :{port}'` (two spaces after `try`).
- `drain: accept() -> fd {fd} from port {peer port} at +{elapsed:.1f} s`.
- Non-Linux: `neveraccept: the backlog+1 rule is Linux's; run it in the lab: just demo 00/04` exit 2.
- Failure: `smoke: FAIL, expected 5 connected and 8 drained, got {done} and {drained}` exit 1.

**Exit codes:** 0 ok, 1 smoke failed, 2 not Linux.

**Must reproduce:** the explicit backlog. Go's `net.Listen` always passes `somaxconn` as the backlog, so the Go port must use `syscall.Socket`, `syscall.SetsockoptInt(SO_REUSEADDR)`, `syscall.Bind`, `syscall.Listen(fd, backlog)`, non-blocking `syscall.Connect` (expect `syscall.EINPROGRESS`), and `syscall.Accept` for the drain. Rust's std `TcpListener::bind` picks its own backlog too, so use `libc::listen(fd, backlog)` (and `libc::connect`, `libc::poll`, `libc::getsockopt(SO_ERROR)`, `libc::accept`) via the `libc` crate. `see.sh` checks `ss -lnt` for `LISTEN 5 4` against the Python demo; your port must produce the same `5 connected, 3 pending`.

## 0.5 `demos/00/05`: blocking echo vs raw epoll echo

**Flags:** `--mode blocking|epoll` (default `epoll`), `--port N` (default 9005), `--max-clients N` (default 0 = forever), `--smoke`.

**Behaviour:**

- Listener: `socket`, `SO_REUSEADDR`, `bind 127.0.0.1:{port}`, `listen(16)`; in epoll mode set `O_NONBLOCK` on it.
- Blocking: loop `accept` → for each client loop `read(fd, 65536)`; print; on 0 bytes stop; else `write` the bytes back, looping until all of them are written (a `write()` may take fewer), printing each call's real count; then `close` and print. Close the client's fd on any error path too. Count a client as served when it is closed; stop after `max-clients` if non-zero.
- Epoll: `epoll_create1(EPOLL_CLOEXEC)`, add the listener with `EPOLLIN` (level-triggered). Loop `epoll_wait(-1)` and print the ready fds. Listener ready: accept until `EAGAIN` (print the EAGAIN line), set each new fd `O_NONBLOCK`, add it with `EPOLLIN`. On `EMFILE`: print the EMFILE line, sleep 1 s, return to `epoll_wait`. Client ready: read until `EAGAIN`; echo each chunk with one non-blocking `write()`. If it takes only part of the chunk, or returns `EAGAIN`, keep the rest as that client's pending bytes, switch its interest to `EPOLLOUT` (`epoll_ctl(MOD)`), print the short-write line and stop reading it. When a client with pending bytes is ready, write them; once all are gone switch back to `EPOLLIN` and print the drained line. Route events by state (pending bytes or not), not by the event mask. On 0 bytes delete it from epoll, close it, count it served; on `ECONNRESET` or `EPIPE` print the reset line and do the same. Own every accepted fd: close it if `O_NONBLOCK` or `epoll_ctl(ADD)` fails, and close all remaining clients when the loop returns (Go: a map plus `defer`; Rust: `OwnedFd` in a `HashMap`).
- Use `read`/`write` syscalls on the fds (not `recv`/`send`), so the strace output matches the lesson (`read(5, "hello from A\n", 65536) = 13`).

**Smoke:** for each mode in order (blocking, then epoll): start the server on a thread/goroutine with `max-clients 2`, connect clients A and B, A sends `hello from A\n` and must get its echo within 1 s; B sends `hello from B\n` and waits 0.5 s; then A closes; B waits up to 1 s more. Blocking passes if A echoed, B did *not* echo early, and B echoed after A closed. Epoll passes if A echoed and B echoed early. Print each mode's line, then `smoke: OK` (exit 0) or `smoke: FAIL` (exit 1).

**Output lines:**

```text
echo-blocking: pid 82739, listening fd 3 on 9005
accept() = fd 4 from port 62142
read(4) = 13
write(4) = 13
read(4) = 0
close(4)
echo-epoll: pid 83438, listening fd 3 on 9005, epoll fd 4
epoll_wait() = 1 ready: fd 3
accept() = fd 5 from port 62192, O_NONBLOCK, added to epoll
accept() = EAGAIN (accept queue empty)
accept() = EMFILE (no free fd; the connection stays queued)
epoll_wait() = 2 ready: fd 7, fd 8
read(5) = EAGAIN (drained; back to epoll_wait)
write(5) = 49510 (short write: 16026 bytes pending, waiting for EPOLLOUT)
write(5) = EAGAIN (send buffer full: 65536 bytes pending, waiting for EPOLLOUT)
epoll_ctl(MOD, fd 5, EPOLLIN): output drained, reading again
fd 5: ECONNRESET (Connection reset by peer); closing
smoke: blocking: B echoed only after A hung up: True
smoke: epoll: B echoed while A was still connected: True
smoke: OK
```

- The smoke lines print the boolean as `True`/`False` (match Python's capitalisation).
- Non-Linux: `echo: epoll is Linux-only; run it in the lab: just demo 00/05 python` (say `go`/`rust`) exit 2. Other OS errors in the server: `echo: {ERRNO NAME} ({strerror})` exit 1.

**Exit codes:** 0 ok, 1 smoke failed or server error, 2 not Linux.

**Must reproduce (the point of the lesson):** raw syscalls, not the runtime. Go must call `syscall.Socket`, `syscall.Bind`, `syscall.Listen`, `syscall.Accept4` (or `Accept`), `syscall.Read`, `syscall.Write`, `syscall.Close`, `syscall.SetNonblock` (that is `fcntl(F_SETFL, O_NONBLOCK)`; CPython uses `ioctl(FIONBIO)`, and the lesson points out the difference), and `syscall.EpollCreate1`, `syscall.EpollCtl`, `syscall.EpollWait` directly, **not** `net.Listen`. Rust must use `libc::socket`, `bind`, `listen`, `accept4`, `read`, `write`, `close`, `fcntl`, `epoll_create1`, `epoll_ctl`, `epoll_wait` through the `libc` crate with a minimal `Cargo.toml` (bin `demo-00-05`), **not** `std::net::TcpListener` or mio. On arm64 strace shows `epoll_pwait` for all three; that is expected.

## 0.6 `demos/00/06`: one echo server, three runtimes

**Decision:** the Author wrote **minimal working Go and Rust versions** (`demos/00/06/go/main.go`, `demos/00/06/rust/{main.rs,Cargo.toml,Cargo.lock}`) so that the lesson's See It could strace all three runtimes; `demos/00/06/see.sh` builds and traces them. The Porter refines them (comments, structure, error handling) but must keep the behaviour the See It shows and the output lines below. If you change anything `see.sh` relies on (binary name `demo-00-06`, the banner, the explicit read/write loop, the tokio feature set), tell the Author so the lesson's excerpts can be re-captured.

**Flags:** `--port N` (default 9006), `--buf-size N` (default 65536: the bytes per read, and in Go and Rust the size of the buffer allocated per connection), `--smoke` (always uses 65536).

**Behaviour:** echo server on `127.0.0.1:{port}` using the runtime's own networking. Python: `asyncio.start_server`. Go: `net.Listen` + one goroutine per connection with an explicit `conn.Read(buf)` / `conn.Write(buf[:n])` loop over a 64 KiB buffer (not `io.Copy`, which would use `splice` and hide the reads). Rust: tokio multi-thread runtime (`#[tokio::main]`, features `rt-multi-thread`, `net`, `io-util`, `macros` only, `default-features = false`), `TcpListener` + one `tokio::spawn`ed task per connection with `read` / `write_all` over a 64 KiB `Vec`. On disconnect print the per-connection line (not in smoke mode).

**Smoke:** start the server in-process, run 50 concurrent clients that each connect, send `hello from client {n}\n`, read exactly that many bytes back and compare; pass if all 50 match.

**Output lines** (the parenthetical is runtime-specific on purpose: it is what the lesson compares):

```text
echo-asyncio: pid 10330, listening on 127.0.0.1:9006 (EpollSelector, 1 thread)
echo-goroutines: pid 13393, listening on 127.0.0.1:9006 (GOMAXPROCS 14, 5 threads)
echo-tokio: pid 13640, listening on 127.0.0.1:9006 (multi-thread runtime, 14 workers)
port 57232: echoed 8 bytes, closed
smoke: OK, 50 concurrent clients echoed by 1 thread
smoke: OK, 50 concurrent clients echoed by 21 threads
smoke: OK, 50 concurrent clients echoed by 14 worker threads
smoke: FAIL, 49 of 50 clients got their echo
```

- Go's thread count is `pprof.Lookup("threadcreate").Count()`; Rust's worker count is `std::thread::available_parallelism()` (tokio's default worker count).
- Bind failure: `echo-goroutines: {error}` / `echo-tokio: {error}` exit 1. Rust unknown argument: `echo-tokio: unknown argument {arg}` exit 2.
- `--buf-size` must be positive: `echo-asyncio: --buf-size must be a positive byte count` (`echo-goroutines: …`, `echo-tokio: …`) and exit 2, checked before any server starts. A zero-length read returns at once (Go's returns `(0, nil)`, so a handler would spin).

**Exit codes:** 0 ok, 1 smoke failed or bind error, 2 bad argument (a non-positive `--buf-size` in every port; an unknown or malformed flag).

**Must reproduce (what the See It shows):** Go: `accept4(…, SOCK_CLOEXEC|SOCK_NONBLOCK)`, `read(4) = -1 EAGAIN`, the netpoller's `epoll_pwait(…, -1) = 1`, then `read(4, "hello 1\n", 65536) = 8`, possibly on another OS thread; `GODEBUG=schedtrace=1000` works unchanged. Rust: 14 threads named `tokio-rt-worker` (one per CPU) plus `main`; `recvfrom`/`sendto(…, MSG_NOSIGNAL)`; a worker blocked in `epoll_pwait(…, 1024, -1, …)`. Optional extras that need more crates (`tokio-console` via `console-subscriber`, `RUST_LOG=mio=trace` via `tracing-subscriber`) belong behind a Cargo feature that is off by default, so the smoke build stays small.

## Checklist for the Porter

- [ ] `demos/00/0{1..6}/go/main.go` and `rust/main.rs` exist (0.6 refined, not rewritten from scratch).
- [ ] `just demo 00/LL go --smoke` and `just demo 00/LL rust --smoke` pass for every lesson (0.2 needs network; it is skipped with `CI_OFFLINE=1`).
- [ ] `gofmt -l demos/00` is empty; `go vet` passes on each file; `cargo fmt --check` and `cargo clippy -- -D warnings` pass for each Cargo port.
- [ ] Each lesson's `Code: Go` and `Code: Rust` sections are filled and the `<!-- PORTER: … -->` comments are gone; Key Files rows added; `just lint-docs` passes.
- [ ] Output lines match this file and the Python demo.
