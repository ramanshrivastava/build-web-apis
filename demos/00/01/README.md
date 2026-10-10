# Demo 0.1: an AF_PACKET sniffer

Lesson: [Electrons to Frames](../../../docs/00-how-bytes-move/01-ELECTRONS-TO-FRAMES.md)

An `AF_PACKET` socket receives whole Ethernet frames from the kernel, header included, before IP, TCP or UDP look at them. The demo binds one to an interface and prints, for each frame, the source and destination MAC, the EtherType, the frame length, the direction the kernel reports (`sll_pkttype`), and a one-line IPv4 summary.

```text
sniff: AF_PACKET socket fd=3 bound to lo (ifindex 1)
frame 1: 00:00:00:00:00:00 > 00:00:00:00:00:00 type 0x0800 IPv4 len 50 outgoing | UDP 127.0.0.1:59186 > 127.0.0.1:9001
frame 2: 00:00:00:00:00:00 > 00:00:00:00:00:00 type 0x0800 IPv4 len 50 host | UDP 127.0.0.1:59186 > 127.0.0.1:9001
smoke: OK, the datagram to :9001 crossed lo twice (outgoing, host)
```

## Run

```bash
just demo 00/01 python                    # 10 frames on lo
just demo 00/01 python --iface eth0 -n 5  # 5 frames on the lab's eth0
just demo 00/01 all --smoke               # self-check in all three languages
just see 00/01                            # the lesson's See It
```

`AF_PACKET` is Linux-only and needs `CAP_NET_RAW`. On macOS, `run.sh` re-runs itself in the lab container, where it is root; on a Linux host it uses `sudo -n`.

| Flag | Default | Meaning |
|------|---------|---------|
| `--iface IFACE` | `lo` | Interface to bind the packet socket to |
| `-n`, `--count N` | `10` | Frames to print before exiting |
| `--timeout S` | `10` | Give up after S seconds |
| `--smoke` | off | Bind a UDP receiver on `127.0.0.1:9001`, send 3 datagrams to it, and pass when the sniffer sees both the outgoing and the host copy |

## What to look for

- **Every frame on `lo` shows up twice.** The kernel hands packet sockets a copy on transmit (`outgoing`, from `dev_queue_xmit_nit()`) and again on receive (`host`). `tcpdump -i lo` shows one, because libpcap drops the outgoing copy on loopback.
- **Loopback MACs are all zeros.** `lo` has no wire, but the kernel still builds a 14-byte Ethernet header so that every packet tap sees the same layout.
- **On `eth0` the MACs are real** and match `tcpdump -e` and `ip neigh`.

## Files

| File | Role |
|------|------|
| `python/main.py` | The sniffer (Python, stdlib) |
| `go/main.go`, `rust/main.rs` | The same program in Go and Rust (see `PORT-SPEC.md`) |
| `run.sh` | `run.sh LANG [--smoke] [ARGS...]` |
| `see.sh` | The lesson's See It: the sniffer, `tcpdump -e`, NIC counters, IRQs, `softnet_stat`, the MTU |
