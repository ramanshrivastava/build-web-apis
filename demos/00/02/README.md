# Demo 0.2: a DNS query built by hand

Lesson: [Addressing and Routing](../../../docs/00-how-bytes-move/02-ADDRESSING-AND-ROUTING.md)

The demo packs a DNS query (RFC 1035: a 12-byte header, then the question as length-prefixed labels) into a byte string, sends it with one `sendto()` on a UDP socket, and parses whatever `recvfrom()` returns, name compression included. If the answer comes back with the TC (truncated) bit set, it asks again over TCP with a 2-byte length prefix, the way every real resolver does.

```text
dns: resolver 192.168.65.7:53
query: example.com A id=0x47cf, 29 bytes
  0000  47 cf 01 00 00 01 00 00 00 00 00 00 07 65 78 61  G............exa
  0010  6d 70 6c 65 03 63 6f 6d 00 00 01 00 01           mple.com.....
sendto() 29 bytes -> 192.168.65.7:53 (UDP)
recvfrom() 83 bytes <- 192.168.65.7:53
header: id=0x47cf qr=1 tc=0 rd=1 ra=1 rcode=NOERROR questions=1 answers=2
answer: example.com A 172.66.147.243 ttl=377
```

## Run

```bash
just demo 00/02 python                          # A record for example.com
just demo 00/02 python --type TXT google.com    # TC=1 over UDP, then TCP
just demo 00/02 python --server 1.1.1.1 --tcp example.com
just demo 00/02 all --smoke                     # skipped when CI_OFFLINE=1
just see 00/02                                  # the lesson's See It (needs network)
```

This is the one Module 0 demo that needs the internet: it asks a real resolver. `run.sh --smoke` prints `skip:` and exits 0 when `CI_OFFLINE=1`, which the CI `demos` job sets. The demo uses plain sockets, so it also runs natively on macOS.

| Argument | Default | Meaning |
|----------|---------|---------|
| `NAME` | `example.com` | The name to look up |
| `--type T` | `A` | `A`, `AAAA`, `CNAME`, `NS`, `SOA` or `TXT` |
| `--server IP` | first IPv4 `nameserver` in `/etc/resolv.conf` | Resolver to ask |
| `--port N` | `53` | Resolver port |
| `--tcp` | off | Skip UDP and ask over TCP |
| `--smoke` | off | `example.com A` over UDP and over TCP; pass on at least one A record |

## What to look for

- **The query is 29 bytes.** The hex dump the demo prints is byte-for-byte the UDP payload in `tcpdump -X`.
- **`tc=1`**: a big answer (`TXT google.com`) does not fit in 512 bytes of UDP, so the server sends what fits and sets TC; the demo retries over TCP and gets all of it.
- **The source address depends on the route.** In the lab the resolver is reached through `services1` from `192.168.65.6`, and the internet through `eth0` from `192.168.65.3`.

## Files

| File | Role |
|------|------|
| `python/main.py` | The DNS client (Python, stdlib) |
| `go/main.go`, `rust/main.rs` | The same program in Go and Rust (see `PORT-SPEC.md`) |
| `run.sh` | `run.sh LANG [--smoke] [ARGS...]`; skips `--smoke` when `CI_OFFLINE=1` |
| `see.sh` | The lesson's See It: `ip route get`, ARP, `tcpdump -X`, `strace`, a DNAT rule and `conntrack -L`, `dig +trace` |
