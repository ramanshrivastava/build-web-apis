"""Lesson 0.2 demo: a DNS query built by hand and sent over UDP (RFC 1035).

No resolver library: the 12-byte header and the question are packed with
struct, sent with one sendto(), and the answer is parsed from the bytes that
recvfrom() returns, name compression included. If the server sets the TC
(truncated) bit, the query is repeated over TCP with a 2-byte length prefix
(RFC 1035 section 4.2.2, RFC 7766): DNS is UDP until it isn't.

    python3 main.py example.com              # A record via the resolver in /etc/resolv.conf
    python3 main.py --type TXT google.com    # big answers set TC=1 and fall back to TCP
    python3 main.py --server 1.1.1.1 --tcp example.com
    python3 main.py --smoke                  # needs network; run.sh skips it with CI_OFFLINE=1
"""

from __future__ import annotations

import argparse
import random
import socket
import struct
import sys

HEADER = struct.Struct("!HHHHHH")  # id, flags, qdcount, ancount, nscount, arcount
TYPES = {"A": 1, "NS": 2, "CNAME": 5, "SOA": 6, "TXT": 16, "AAAA": 28}
TYPE_NAMES = {v: k for k, v in TYPES.items()}
CLASS_IN = 1
RCODES = {0: "NOERROR", 1: "FORMERR", 2: "SERVFAIL", 3: "NXDOMAIN", 4: "NOTIMP", 5: "REFUSED"}
UDP_LIMIT = 512  # RFC 1035 2.3.4: a UDP message without EDNS(0) is at most 512 bytes


def hexdump(data: bytes) -> list[str]:
    """xxd-style lines: offset, 16 bytes in hex, then the printable ASCII."""
    lines = []
    for offset in range(0, len(data), 16):
        chunk = data[offset : offset + 16]
        hexes = " ".join(f"{b:02x}" for b in chunk)
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"  {offset:04x}  {hexes:<47}  {text}")
    return lines


def encode_name(name: str) -> bytes:
    """example.com -> 07 'example' 03 'com' 00: length-prefixed labels."""
    out = b""
    for label in name.rstrip(".").split("."):
        out += bytes([len(label)]) + label.encode("ascii")
    return out + b"\x00"


def build_query(query_id: int, name: str, qtype: int) -> bytes:
    flags = 0x0100  # QR=0 (query), OPCODE=0, RD=1: please recurse for me
    header = HEADER.pack(query_id, flags, 1, 0, 0, 0)  # one question, nothing else
    return header + encode_name(name) + struct.pack("!HH", qtype, CLASS_IN)


def decode_name(msg: bytes, offset: int) -> tuple[str, int]:
    """Read a (possibly compressed) name at offset; return it and the offset after it."""
    labels, end, jumps = [], None, 0
    while True:
        length = msg[offset]
        if length & 0xC0 == 0xC0:  # pointer: the rest of the name lives elsewhere
            if end is None:
                end = offset + 2
            offset = ((length & 0x3F) << 8) | msg[offset + 1]
            jumps += 1
            if jumps > 20:
                raise ValueError("compression loop")
            continue
        if length == 0:
            return ".".join(labels) or ".", end if end is not None else offset + 1
        labels.append(msg[offset + 1 : offset + 1 + length].decode("ascii", "replace"))
        offset += 1 + length


def describe_rdata(msg: bytes, rtype: int, start: int, rdlength: int) -> str:
    rdata = msg[start : start + rdlength]
    if rtype == 1 and rdlength == 4:
        return socket.inet_ntop(socket.AF_INET, rdata)
    if rtype == 28 and rdlength == 16:
        return socket.inet_ntop(socket.AF_INET6, rdata)
    if rtype in (2, 5):
        return decode_name(msg, start)[0]
    if rtype == 16:
        text, i = [], 0
        while i < len(rdata):
            text.append(rdata[i + 1 : i + 1 + rdata[i]].decode("utf-8", "replace"))
            i += 1 + rdata[i]
        joined = " ".join(text)
        return f'"{joined[:60]}"' + ("..." if len(joined) > 60 else "")
    return f"({rdlength} bytes)"


def parse_response(msg: bytes) -> tuple[dict[str, int], list[str]]:
    query_id, flags, qd, an, ns, ar = HEADER.unpack_from(msg)
    header = {
        "id": query_id,
        "qr": flags >> 15,
        "tc": (flags >> 9) & 1,
        "rd": (flags >> 8) & 1,
        "ra": (flags >> 7) & 1,
        "rcode": flags & 0xF,
        "qd": qd,
        "an": an,
    }
    offset = HEADER.size
    for _ in range(qd):  # skip the echoed question
        offset = decode_name(msg, offset)[1] + 4
    answers = []
    for _ in range(an):
        name, offset = decode_name(msg, offset)
        rtype, _cls, ttl, rdlength = struct.unpack_from("!HHIH", msg, offset)
        offset += 10
        value = describe_rdata(msg, rtype, offset, rdlength)
        answers.append(f"{name} {TYPE_NAMES.get(rtype, rtype)} {value} ttl={ttl}")
        offset += rdlength
    return header, answers


def ask_udp(server: str, port: int, query: bytes) -> bytes:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(3.0)
        sent = sock.sendto(query, (server, port))  # one datagram, no connection
        print(f"sendto() {sent} bytes -> {server}:{port} (UDP)")
        reply, peer = sock.recvfrom(4096)
        print(f"recvfrom() {len(reply)} bytes <- {peer[0]}:{peer[1]}")
        return reply


def ask_tcp(server: str, port: int, query: bytes) -> bytes:
    with socket.create_connection((server, port), timeout=3.0) as sock:
        framed = struct.pack("!H", len(query)) + query  # TCP is a stream: add a length
        sock.sendall(framed)
        print(f"send() {len(framed)} bytes -> {server}:{port} (TCP, 2-byte length + query)")
        reply = b""
        while len(reply) < 2 or len(reply) < 2 + struct.unpack_from("!H", reply)[0]:
            chunk = sock.recv(65535)
            if not chunk:
                raise ConnectionError("server closed before the full answer arrived")
            reply += chunk
        print(f"recv() {len(reply)} bytes <- {server}:{port} (length prefix says {len(reply) - 2})")
        return reply[2:]


def system_resolver() -> str | None:
    try:
        with open("/etc/resolv.conf") as conf:
            for line in conf:
                parts = line.split()
                if len(parts) >= 2 and parts[0] == "nameserver" and ":" not in parts[1]:
                    return parts[1]
    except OSError:
        return None
    return None


def show(header: dict[str, int], answers: list[str]) -> None:
    rcode = RCODES.get(header["rcode"], str(header["rcode"]))
    print(
        f"header: id=0x{header['id']:04x} qr={header['qr']} tc={header['tc']} rd={header['rd']} "
        f"ra={header['ra']} rcode={rcode} questions={header['qd']} answers={header['an']}"
    )
    for answer in answers:
        print(f"answer: {answer}")


def resolve(name: str, qtype: str, server: str, port: int, force_tcp: bool) -> tuple[dict, list]:
    query_id = random.getrandbits(16)
    query = build_query(query_id, name, TYPES[qtype])
    print(f"query: {name} {qtype} id=0x{query_id:04x}, {len(query)} bytes")
    for line in hexdump(query):
        print(line)
    reply = ask_tcp(server, port, query) if force_tcp else ask_udp(server, port, query)
    header, answers = parse_response(reply)
    if header["id"] != query_id:
        raise ValueError(f"reply id 0x{header['id']:04x} does not match query")
    show(header, answers)
    if header["tc"] and not force_tcp:
        print(f"truncated: the answer did not fit in {UDP_LIMIT} bytes of UDP; retrying over TCP")
        header, answers = parse_response(ask_tcp(server, port, query))
        show(header, answers)
    return header, answers


def main() -> int:
    parser = argparse.ArgumentParser(description="Send a hand-built DNS query over UDP.")
    parser.add_argument("name", nargs="?", default="example.com")
    parser.add_argument("--type", default="A", choices=sorted(TYPES), help="record type")
    parser.add_argument("--server", help="resolver IP (default: first in /etc/resolv.conf)")
    parser.add_argument("--port", type=int, default=53)
    parser.add_argument("--tcp", action="store_true", help="skip UDP, ask over TCP")
    parser.add_argument("--smoke", action="store_true", help="A for example.com over UDP+TCP")
    args = parser.parse_args()
    server = args.server or system_resolver()
    if server is None:
        print("dns: no IPv4 nameserver in /etc/resolv.conf; pass --server IP")
        return 2
    print(f"dns: resolver {server}:{args.port}")
    try:
        if not args.smoke:
            resolve(args.name, args.type, server, args.port, args.tcp)
            return 0
        udp_header, udp_answers = resolve("example.com", "A", server, args.port, False)
        tcp_header, tcp_answers = resolve("example.com", "A", server, args.port, True)
    except (OSError, ValueError, IndexError, struct.error) as err:
        print(f"dns: FAIL, {err}")
        return 1
    found = [a for a in udp_answers + tcp_answers if " A " in a]
    if udp_header["rcode"] == 0 and tcp_header["rcode"] == 0 and found:
        print(f"smoke: OK, example.com resolved over UDP and TCP ({len(found)} A records)")
        return 0
    print("smoke: FAIL, no A record for example.com")
    return 1


if __name__ == "__main__":
    sys.exit(main())
