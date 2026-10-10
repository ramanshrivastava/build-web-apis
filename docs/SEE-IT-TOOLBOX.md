# See It Toolbox

**Course Conventions**
**Ticketing Project**

---

The course rule is **see the internals**. Every lesson has one `## K. See It:` section that observes the lesson's mechanism with real tools: exact commands, 3–10 lines of real output, and a `demos/<mm>/<ll>/see.sh` that replays it (`just see <mm>/<ll>`). This page is the palette authors pick from, and the reference for running those tools in the lab.

## Rules for a See It

- **At least two tools.** Look from two sides, for example the wire (`tcpdump`) and the socket (`ss`), or the syscall (`strace`) and the runtime (`py-spy`).
- **Exact commands.** Each command is copy-pasteable in `just lab`, with no "something like".
- **Real output.** Paste 3–10 lines captured with that command. Trim with `…`, never edit values. Name the kernel or runtime version when the output depends on it.
- **Reproducible.** `see.sh` replays the observation and passes only if a line matches its `EXPECT=` regex (see `demos/README.md`).

## The Palette

| Layer | Tools | What they show |
|-------|-------|----------------|
| Wire | `tcpdump -i any -nn -X`, `tshark` / Wireshark dissectors (`tcp.analysis`, `http`, `http2`, `websocket`, `quic`, `pgsql`, `redis`), `SSLKEYLOGFILE` | The bytes on the wire: handshakes, windows, retransmits, frames, decrypted TLS |
| Syscalls | `strace -f -tt -e trace=network,desc,epoll_wait`, `ltrace` | The process/kernel boundary: every `accept4`, `read`, `write`, `epoll_wait`, with timestamps |
| Socket state | `ss -tnip`, `ss -lnt`, `/proc/net/tcp`, `/proc/<pid>/fd`, `lsof -p`, `nstat`, `sysctl net.*` | Queues (Recv-Q/Send-Q), windows, cwnd, rtt, states, fd tables, kernel counters |
| Runtime hood | Python: `PYTHONASYNCIODEBUG=1`, `py-spy`, `gdb -p` + `break sock_recv`, `Lib/selectors.py`. Go: `GODEBUG=schedtrace=1000,http2debug=2`, `go tool pprof`, `go tool trace`, `runtime/netpoll_epoll.go`, `net/http/server.go`. Rust: `RUST_LOG=trace`, `tokio-console`, `cargo flamegraph`, `mio/.../epoll.rs`, `tokio/src/runtime/io/driver.rs`, `hyper/src/proto/h1/` | How each runtime turns readiness into a resumed coroutine, goroutine or future |
| Data | `EXPLAIN (ANALYZE, BUFFERS)`, `pg_locks` ⋈ `pg_stat_activity`, `log_statement=all`, `log_lock_waits=on`, `pg_stat_replication`, `redis-cli MONITOR` / `SLOWLOG` | Query plans, who holds and who waits for which lock, every statement, replication lag |
| Edge | `curl -v --trace-ascii -`, `openssl s_client -msg -tlsextdebug`, nginx `error_log … debug`, `nginx -T` | Request and response bytes, TLS handshake messages, what the proxy actually did |
| Load / obs | `wrk --latency`, `k6`, `hey`, `/metrics`, the Jaeger waterfall, `perf record` + flamegraph | Latency distributions, throughput, where time goes |

### Invocations you will see often

| Command | Shows |
|---------|-------|
| `tcpdump -i any -nn -X 'tcp port 8080'` | Packets with hex + ASCII payload, numeric hosts and ports |
| `tcpdump -i any -nn -w captures/x.pcap ...` then `tshark -r captures/x.pcap -Y http` | Capture now, dissect later (Wireshark on the host opens the same file) |
| `strace -f -tt -e trace=network,desc,epoll_wait -p <pid>` | Syscalls of a running server, all threads, with microsecond timestamps |
| `strace -c -f -p <pid>` | Syscall counts and time: the cheapest profile there is |
| `ss -tni 'sport = :8080'` | Per-connection TCP internals: `cwnd`, `rtt`, `rcv_space`, `bytes_acked` |
| `ss -lnt` | Listening sockets; Recv-Q is the accept-queue depth, Send-Q its limit |
| `nstat -az TcpExtListenOverflows TcpRetransSegs` | Kernel counters (`-a` absolute, `-z` include zeros) |
| `ls -l /proc/<pid>/fd` | Every open fd, sockets as `socket:[inode]` |
| `py-spy dump --pid <pid>` | Every Python thread's stack, right now |
| `GODEBUG=schedtrace=1000 ./ticketing api` | Go scheduler state every second: Ps, Ms, runnable goroutines |
| `SELECT … FROM pg_locks l JOIN pg_stat_activity a USING (pid)` | Who holds and who waits for which lock |

The capture wrappers in `scripts/capture/` package the common cases and write to `captures/<timestamp>/` (gitignored): `tcpdump.sh` (timed pcap, then a `-nn -X` dump), `strace.sh` (attach or launch, then a syscall summary) and `ss-watch.sh` (repeated `ss -tnip` snapshots).

## The Lab

`tcpdump -i any`, `strace`, `ss`, `/proc`, `perf`, `conntrack` and `tc` are Linux tools; most readers write code on macOS. Every See It therefore runs in the lab container defined by `infra/lab/Dockerfile`:

```bash
just lab                 # interactive shell, repo mounted at /work
just lab ss -lnt         # one command in the lab
just see 03/04           # one lesson's see.sh in the lab (directly on Linux hosts)
```

What the lab is:

- **Ubuntu 24.04** with the whole palette: tcpdump, tshark, strace, ltrace, iproute2 (`ss`, `ip`, `nstat`, `tc`), dnsutils, lsof, procps, conntrack, iptables, ethtool, perf, gdb, py-spy, wrk, hey, k6, curl, jq, netcat, openssl, psql, redis-cli and just.
- **The three toolchains** (uv, Go, Rust), so `run.sh` and `see.sh` can run every port inside the lab. Build output goes to `/root/.cache`, not into the bind-mounted repo, so macOS and Linux artifacts never mix.
- **Privileges for observation**: `cap_add: [NET_ADMIN, NET_RAW, SYS_PTRACE]` (capture, `tc`, `strace -p`), `pid: host` (see and trace host processes), `network_mode: host` (share the host's network namespace).

On Docker Desktop, "host" means Docker's Linux VM, not macOS. Run the server you want to observe *inside the lab* (a second `just lab` shell works well), or observe a compose service, since compose containers also run in that VM. Postgres and Redis published by `just up` are reachable from the lab at `localhost:5432` and `localhost:6379`.

### Kernel caveats

The lab shares the host's kernel: Docker Desktop's VM kernel on macOS, the runner's kernel in CI. Three consequences:

- **Virtual NICs hide hardware.** Lesson 0.1's ring-buffer and interrupt counters (`ethtool -S`, `/proc/interrupts`) are thin on a veth or virtio NIC. The lesson says what you would see on bare metal, and shows what the VM does expose.
- **Optional kernel modules may be missing.** If `tc qdisc add dev lo root netem delay 100ms` fails with `Specified qdisc kind is unknown`, the VM kernel lacks `sch_netem`. Use a Linux host or the CI runner for that step.
- **Counters and `ss -i` fields vary by kernel version.** Each See It names the kernel (`uname -r`) it was captured on.

## Lab vs macOS

You can run some tools natively on macOS, but lessons are written against the lab.

| Tool | Lab (Ubuntu 24.04) | macOS host | Notes |
|------|--------------------|------------|-------|
| tcpdump | yes | built in | macOS: use `-i lo0` for loopback (no `-i any`); needs `sudo` |
| tshark / Wireshark | tshark | `brew install --cask wireshark` | Open lab pcaps from `captures/` in the GUI |
| strace, ltrace | yes | no | `dtruss` needs SIP disabled; do not. Use the lab |
| ss, `/proc`, nstat, sysctl `net.*` | yes | no | `netstat -an`, `lsof -i` and `nettop` are rough macOS equivalents; lessons do not use them |
| conntrack, iptables, tc, ip, ethtool | yes | no | Linux networking only |
| perf | yes | no | Linux only. macOS has Instruments, which is not used here |
| gdb | yes | `lldb` | Lesson 0.6's `break sock_recv` is written for gdb |
| py-spy | yes | `uv tool install py-spy` | Needs `sudo` on macOS |
| `go tool pprof` / `trace` | yes | yes | Ships with Go |
| tokio-console | `cargo install --locked tokio-console` | same | Not baked into the image; lesson 0.6 installs it |
| wrk, hey, k6 | yes | `brew install wrk hey k6` | Host load generators measure a different network path; see lesson 6.1 |
| curl, dig | yes | built in | |
| openssl | OpenSSL 3 | LibreSSL | `s_client -msg -tlsextdebug` output differs; use the lab |
| psql, redis-cli | yes | `brew install libpq redis` | `just migrate` needs `psql` on the host, or run it in `just lab` |

## In CI

The `demos` job runs on `ubuntu-latest` with `tcpdump` and `strace` installed by apt, and runs every `see.sh` with `sudo` where needed (`common.sh` sets `$SUDO`). A `see.sh` that needs another tool calls `require_tool`, which fails loudly instead of skipping, and the lesson's PR adds the apt package to the job.

## Decrypting TLS

For lessons 3.3, 3.6 and 5.1: set `SSLKEYLOGFILE=captures/keys.log` for the client (curl, Python `ssl`, Go `crypto/tls` via `KeyLogWriter`, rustls via `KeyLogFile`), capture with tcpdump, then:

```bash
tshark -r captures/x.pcap -o tls.keylog_file:captures/keys.log -Y http2
```

The handshake stays readable without keys, which is the point of lesson 5.1's `(tls-does-not-hide-sni)`.
