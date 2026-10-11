"""Lesson 0.1 demo: an AF_PACKET sniffer that prints each frame's MACs and EtherType.

An AF_PACKET socket receives whole link-layer frames, Ethernet header included,
straight from the kernel's receive and transmit paths (net/packet/af_packet.c),
before IP, TCP or UDP have looked at them. Linux only, and it needs CAP_NET_RAW
(root in the lab).

    python3 main.py                     # 10 frames on lo
    python3 main.py --iface eth0 -n 5   # 5 frames on the lab's eth0
    python3 main.py --smoke             # send a UDP datagram on lo and find its frames
"""

from __future__ import annotations

import argparse
import socket
import struct
import sys
import time

ETH_P_ALL = 0x0003  # include/uapi/linux/if_ether.h: every protocol
ETH_HEADER = struct.Struct("!6s6sH")  # dst MAC, src MAC, EtherType (network byte order)
ETHERTYPES = {0x0800: "IPv4", 0x0806: "ARP", 0x86DD: "IPv6", 0x8100: "802.1Q"}
# sll_pkttype, include/uapi/linux/if_packet.h: who the frame was for
PKTTYPES = {0: "host", 1: "broadcast", 2: "multicast", 3: "otherhost", 4: "outgoing"}
IP_PROTOS = {1: "ICMP", 6: "TCP", 17: "UDP"}
SMOKE_PORT = 9001
SMOKE_PAYLOAD = b"m0 smoke"


def mac(raw: bytes) -> str:
    return ":".join(f"{b:02x}" for b in raw)


def describe_ipv4(packet: bytes) -> tuple[str, int | None]:
    """One-line IPv4 summary, plus the UDP/TCP destination port if there is one."""
    if len(packet) < 20:
        return "short IPv4 header", None
    version, ihl = packet[0] >> 4, (packet[0] & 0x0F) * 4  # ihl: header length in 32-bit words
    if version != 4 or ihl < 20 or len(packet) < ihl:
        return "malformed IPv4 header", None
    proto = packet[9]
    src, dst = socket.inet_ntoa(packet[12:16]), socket.inet_ntoa(packet[16:20])
    name = IP_PROTOS.get(proto, f"proto {proto}")
    offset = (struct.unpack_from("!H", packet, 6)[0] & 0x1FFF) * 8  # fragment offset, bytes
    if offset:  # a later fragment carries payload bytes, not the TCP/UDP header
        return f"{name} {src} > {dst} fragment at byte {offset}", None
    if proto in (6, 17) and len(packet) >= ihl + 4:
        sport, dport = struct.unpack_from("!HH", packet, ihl)
        return f"{name} {src}:{sport} > {dst}:{dport}", dport
    return f"{name} {src} > {dst}", None


def describe(frame: bytes, pkttype: int) -> tuple[str, int, int | None]:
    """Frame summary line, its EtherType, and the transport destination port (if any)."""
    dst, src, ethertype = ETH_HEADER.unpack_from(frame)
    payload = frame[ETH_HEADER.size :]
    line = (
        f"{mac(src)} > {mac(dst)} type 0x{ethertype:04x} {ETHERTYPES.get(ethertype, '?')} "
        f"len {len(frame)} {PKTTYPES.get(pkttype, pkttype)}"
    )
    dport = None
    if ethertype == 0x0800:
        summary, dport = describe_ipv4(payload)
        line += f" | {summary}"
    return line, ethertype, dport


def open_sniffer(iface: str) -> socket.socket:
    # SOCK_RAW keeps the link-layer header; htons(ETH_P_ALL) asks for every EtherType.
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
    sock.bind((iface, ETH_P_ALL))  # one interface, not all of them
    return sock


def send_smoke_datagrams() -> socket.socket:
    """Send a few UDP datagrams to 127.0.0.1:9001 with a receiver bound, so no ICMP error."""
    receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    receiver.bind(("127.0.0.1", SMOKE_PORT))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
        for _ in range(3):
            sender.sendto(SMOKE_PAYLOAD, ("127.0.0.1", SMOKE_PORT))
    return receiver


def sniff(iface: str, count: int, timeout: float, smoke: bool) -> int:
    try:
        sock = open_sniffer(iface)
    except AttributeError:
        print("sniff: AF_PACKET is Linux-only; run it in the lab: just demo 00/01 python")
        return 2
    except PermissionError:
        print("sniff: AF_PACKET needs CAP_NET_RAW; run as root (the lab runs as root)")
        return 3
    except OSError as err:
        print(f"sniff: cannot bind to {iface!r}: {err.strerror}")
        return 2
    ifindex = socket.if_nametoindex(iface)
    print(f"sniff: AF_PACKET socket fd={sock.fileno()} bound to {iface} (ifindex {ifindex})")
    receiver = send_smoke_datagrams() if smoke else None
    sock.settimeout(0.5)
    deadline = time.monotonic() + timeout
    seen, matched = 0, set()
    while seen < count and time.monotonic() < deadline:
        try:
            # addr = (ifname, protocol, pkttype, hatype, hwaddr): a sockaddr_ll
            frame, addr = sock.recvfrom(65535)
        except TimeoutError:
            continue
        seen += 1
        line, ethertype, dport = describe(frame, addr[2])
        print(f"frame {seen}: {line}")
        if smoke and ethertype == 0x0800 and dport == SMOKE_PORT:
            matched.add(PKTTYPES.get(addr[2], str(addr[2])))
            if {"outgoing", "host"} <= matched:
                break
    sock.close()
    if receiver is not None:
        receiver.close()
    if not smoke:
        return 0
    if {"outgoing", "host"} <= matched:
        print(f"smoke: OK, the datagram to :{SMOKE_PORT} crossed {iface} twice (outgoing, host)")
        return 0
    print(f"smoke: FAIL, saw {sorted(matched) or 'no'} copies of the datagram to :{SMOKE_PORT}")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Print link-layer frames from AF_PACKET.")
    parser.add_argument("--iface", default="lo", help="interface to bind (default: lo)")
    parser.add_argument("-n", "--count", type=int, default=10, help="frames to print (default 10)")
    parser.add_argument("--timeout", type=float, default=10.0, help="give up after N seconds")
    parser.add_argument("--smoke", action="store_true", help="send UDP on lo, expect its frames")
    args = parser.parse_args()
    if args.smoke:
        return sniff("lo", count=50, timeout=5.0, smoke=True)
    return sniff(args.iface, args.count, args.timeout, smoke=False)


if __name__ == "__main__":
    sys.exit(main())
