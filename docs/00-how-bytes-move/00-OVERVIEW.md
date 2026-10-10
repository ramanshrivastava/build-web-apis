# Module 0: How Bytes Move

> Before you write an API, watch a byte travel: physics moves it, framing bounds it, addressing directs it, windows pace it, buffers hold it.

---

## What this module is

Module 0 has no app code. It follows one byte from a voltage change on a wire to the moment a Python coroutine, a goroutine or a Rust future resumes with it. There are six steps: the physical layer and the NIC, addressing and routing, TCP's flow and congestion control, the kernel's buffers and queues, the socket syscalls, and how the three runtimes wrap those syscalls.

Each lesson ships a small demo in all three languages (an `AF_PACKET` sniffer, a hand-built DNS query, a deliberately slow reader, a server that never calls `accept()`, and raw `epoll` echo servers) and observes it with `tcpdump`, `ss`, `strace` and `/proc` in the lab. The module also hardens the tooling every later lesson depends on: [`infra/lab/Dockerfile`](infra/lab/Dockerfile), [`scripts/capture/`](scripts/capture/) and [`scripts/see/common.sh`](scripts/see/common.sh).

## Why a dedicated module

Most API courses start at the framework, so the first time a developer meets a full accept queue, a zero window or a blocked `write()` is in production. Every later module leans on this one. Lesson 1.5's slowloris stall is 0.3's receive window and 0.4's send buffer. Lesson 2.4's "frameworks do not change the syscalls" is 0.5 and 0.6. Lessons 6.3 (pool exhaustion) and 7.4 (load shedding) apply the same bounded-buffer idea one level up. Learn it once, at the bottom, and every later mechanism is a variation rather than a new fact.

## The flow question

The course asks one question at every layer: **what makes data flow, and what makes it stop?** In this module the answer is literal. Signals and DMA move bytes, framing bounds them, addresses direct them, windows pace them, and buffers hold them. Each lesson's first mental model names the mover and the stopper at its layer: the NIC ring that drops when full (0.1), the NAT entry that expires (0.2), the receive window that closes to zero (0.3), the accept queue that overflows (0.4), the `EAGAIN` that tells a non-blocking socket to come back later (0.5), and the event loop that parks a coroutine until `epoll_wait()` says go (0.6).

## Lessons

| # | Lesson | Status |
|---|--------|--------|
| 0.1 | Electrons to Frames (`01-ELECTRONS-TO-FRAMES.md`) | Planned |
| 0.2 | Addressing and Routing (`02-ADDRESSING-AND-ROUTING.md`) | Planned |
| 0.3 | TCP Flow and Congestion (`03-TCP-FLOW-AND-CONGESTION.md`) | Planned |
| 0.4 | Kernel Stack and Buffers (`04-KERNEL-STACK-AND-BUFFERS.md`) | Planned |
| 0.5 | Socket Syscalls (`05-SOCKET-SYSCALLS.md`) | Planned |
| 0.6 | How Runtimes Wrap Syscalls (`06-HOW-RUNTIMES-WRAP-SYSCALLS.md`) | Planned |

Status moves `Planned` → `In progress` → `Done`. Lesson files appear in this folder as `NN-TITLE.md` and follow [`docs/LESSON-SKELETON.md`](docs/LESSON-SKELETON.md).

### 0.1 Electrons to Frames

Signals, the NIC, DMA rings, interrupts and NAPI, Ethernet framing, MTU.

- **Demo:** an `AF_PACKET` sniffer printing MACs and EtherTypes
- **App:** none (Module 0 has no app code)
- **See It:** `ip -s link`, `ethtool -S`, `/proc/interrupts`, `/proc/net/softnet_stat`, `tcpdump -e`, shrinking the MTU and `ping -M do`
- **Diagram:** NIC → ring buffer → softirq → `sk_buff`
- **Reality checks:** `(ring-buffer-drops)`, `(mtu-is-not-1500)`

### 0.2 Addressing and Routing

IP, ARP, routing tables, NAT, DNS, UDP.

- **Demo:** a hand-built DNS query over UDP
- **App:** none
- **See It:** `ip route get`, `ip neigh`, `tcpdump 'arp or udp port 53' -X`, `dig +trace`, `conntrack -L`, `strace -e sendto,recvfrom`
- **Diagram:** packet path host → router → NAT
- **Reality checks:** `(dns-is-udp-until-it-isnt)`, `(nat-is-state)`

### 0.3 TCP Flow and Congestion

The handshake, seq/ack, the receive window, Nagle and delayed ACK, cwnd, CUBIC and BBR.

- **Demo:** `slowreader`, a client with a tiny `SO_RCVBUF`
- **App:** none
- **See It:** `ss -tni`, the zero window in tcpdump and Wireshark, `tc netem delay/loss`, `nstat TcpRetransSegs`
- **Diagram:** the sliding window and congestion phases
- **Reality checks:** `(nagle-and-delayed-ack)`, `(bandwidth-delay-product)`

### 0.4 Kernel Stack and Buffers

`sk_buff`, send and receive buffers, SYN backlog vs accept queue, SYN cookies, TIME_WAIT, port exhaustion.

- **Demo:** `neveraccept`, a server that listens and never accepts
- **App:** none
- **See It:** `ss -lnt` Recv-Q, `nstat ListenOverflows`, `somaxconn`, `/proc/net/tcp` states
- **Diagram:** the two queues
- **Reality checks:** `(backlog-is-two-queues)`, `(time-wait-is-not-a-leak)`

### 0.5 Socket Syscalls

socket/bind/listen/accept/read/write, file descriptors, `O_NONBLOCK` and `EAGAIN`, select/poll/epoll/kqueue.

- **Demo:** a blocking echo server vs an epoll echo server (raw epoll in all three languages)
- **App:** none
- **See It:** `strace -e network,epoll_*`, `/proc/<pid>/fd`, `lsof`, `ulimit -n` exhaustion
- **Diagram:** the syscall boundary between user space and the kernel
- **Reality checks:** `(nonblocking-is-not-async)`, `(epoll-is-not-io)`

### 0.6 How Runtimes Wrap Syscalls

CPython's `socketmodule.c` and GIL release, `selectors.py`, asyncio transports; Go's `internal/poll`, the netpoller and goroutine parking; Rust's mio, the tokio IO driver and hyper.

- **Demo:** the same echo server in asyncio, net + goroutines, and tokio
- **App:** none
- **See It:** `strace -f -e epoll_wait,futex` per runtime, a `gdb` breakpoint in `sock_recv`, `GODEBUG=schedtrace`, `go tool trace`, `tokio-console`, `RUST_LOG=mio=trace`
- **Diagram:** three runtimes over one epoll
- **Reality checks:** `(gil-releases-on-io)`, `(goroutines-are-not-free)`

## What this module does NOT cover

- **Physical-layer encoding** (line codes, PAM4, optics) beyond what explains how a signal becomes a frame.
- **Wireless and cellular radio**: Wi-Fi and 5G framing and scheduling.
- **IPv6 in depth**: noted where it differs (NDP instead of ARP, no NAT by default), but the demos use IPv4.
- **Kernel bypass** (DPDK, XDP, io_uring): named in 0.5 and 0.6 as the next step beyond epoll, not taught.
- **Routing protocols** (BGP, OSPF): the module stops at one host's routing table and a NAT.

## Cross-references

- **Next module:** [`docs/01-http-by-hand/00-OVERVIEW.md`](docs/01-http-by-hand/00-OVERVIEW.md) puts HTTP on top of these sockets.
- **build-ai-agents server-arch:** [`docs/server-arch/01-SYNC-VS-ASYNC.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/server-arch/01-SYNC-VS-ASYNC.md) covers sync vs async from the application side; lesson 0.6 goes underneath it.
- **See It toolbox:** [`docs/SEE-IT-TOOLBOX.md`](docs/SEE-IT-TOOLBOX.md) lists every tool this module introduces, and the lab's kernel caveats.
- **Module gate:** M0: no app code; `apps/` stays untouched (demos, scripts and the lab only). See [`CLAUDE.md`](CLAUDE.md), "Module Gates".
- **Design spec:** [`docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`](docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md) has the binding conventions and this module's full lesson plan.

## Status

Module overview stub, written in Phase 0. All 6 lessons (0.1–0.6) are planned and none are written yet. The module lands as one PR from branch `module/00-how-bytes-move` and is tagged `m0` when the definition of done in [`CONTRIBUTING.md`](CONTRIBUTING.md) passes. The hero diagram (`diagrams/hero.mmd`, rendered to `.excalidraw`, `.svg` and `.png`) is drawn with the module and embedded under the thesis once the first lesson is `Done`.
