"""Lesson 0.3 demo: slowreader, a fast sender and a slow reader with a tiny receive buffer.

The sender writes as fast as send() lets it. The reader asks for a tiny
SO_RCVBUF *before* connect() (the window scale is fixed in the SYN) and reads a
little at a time. TCP flow control does the rest: the reader's receive buffer
fills, it advertises a zero window, the sender's send buffer fills behind it,
and send() blocks. Nothing is lost and nothing is dropped; the flow just stops.

    python3 main.py                              # 4 KiB buffer, 1 KiB every 100 ms, 10 s
    python3 main.py --rcvbuf 65536 --read-size 65536 --interval 0   # a fast reader
    python3 main.py --rcvbuf 0 --read-size 65536 --interval 0       # autotuned buffer
    python3 main.py --smoke                      # 3 s, asserts that send() blocked
"""

from __future__ import annotations

import argparse
import socket
import sys
import threading
import time

CHUNK = b"x" * 65536  # the sender offers 64 KiB per send() call


class Sender:
    """Accept one connection and push bytes until the peer goes away."""

    def __init__(self, listener: socket.socket) -> None:
        self.listener = listener
        self.sent = 0  # bytes the kernel accepted into the send buffer
        self.longest_block = 0.0  # the longest send() call so far, in seconds
        self.send_started: float | None = None  # set while a send() call is in progress

    def blocked_for(self) -> float:
        """How long the current send() call has been waiting (0 if none is)."""
        started = self.send_started
        return 0.0 if started is None else time.monotonic() - started

    def run(self) -> None:
        conn, _ = self.listener.accept()
        with conn:
            while True:
                self.send_started = time.monotonic()
                try:
                    accepted = conn.send(CHUNK)  # blocks while the send buffer is full
                except OSError:
                    return  # the reader closed: EPIPE or ECONNRESET
                self.longest_block = max(self.longest_block, self.blocked_for())
                self.send_started = None
                self.sent += accepted


def connect_reader(port: int, rcvbuf: int) -> socket.socket:
    reader = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    if rcvbuf > 0:
        # Before connect(): the SYN carries the window scale chosen from this buffer,
        # and setting it also turns off receive-buffer autotuning for this socket.
        reader.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, rcvbuf)
        granted = reader.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)
        print(f"slowreader: reader SO_RCVBUF asked {rcvbuf}, kernel set {granted}", flush=True)
    else:
        granted = reader.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)
        print(f"slowreader: reader SO_RCVBUF left to autotuning, starts at {granted}", flush=True)
    reader.connect(("127.0.0.1", port))
    return reader


def run(port: int, rcvbuf: int, read_size: int, interval: float, seconds: float) -> Sender:
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", port))
    listener.listen(1)
    print(f"slowreader: sender listening on 127.0.0.1:{port}", flush=True)
    sender = Sender(listener)
    threading.Thread(target=sender.run, daemon=True).start()

    reader = connect_reader(port, rcvbuf)
    print(
        f"slowreader: reading {read_size} bytes every {interval:.3f} s for {seconds:g} s",
        flush=True,
    )
    read_total, started, next_report = 0, time.monotonic(), 1.0
    while (elapsed := time.monotonic() - started) < seconds:
        read_total += len(reader.recv(read_size))
        if elapsed >= next_report:
            in_kernel = sender.sent - read_total  # sender's Send-Q + reader's Recv-Q
            rate = read_total / elapsed / 1024
            print(
                f"t={next_report:.0f}s sent={sender.sent} read={read_total} "
                f"in-kernel={in_kernel} read-rate={rate:.1f} KiB/s "
                f"send-blocked={sender.blocked_for() * 1000:.0f}ms",
                flush=True,
            )
            next_report += 1.0
        if interval:
            time.sleep(interval)
    sender.longest_block = max(sender.longest_block, sender.blocked_for())
    reader.close()
    listener.close()
    print(
        f"summary: sent={sender.sent} read={read_total} "
        f"longest send() block={sender.longest_block * 1000:.0f} ms",
        flush=True,
    )
    return sender


def main() -> int:
    parser = argparse.ArgumentParser(description="A fast sender meets a slow reader.")
    parser.add_argument("--port", type=int, default=9003)
    parser.add_argument(
        "--rcvbuf", type=int, default=4096, help="reader SO_RCVBUF in bytes (0: autotune)"
    )
    parser.add_argument("--read-size", type=int, default=1024, help="bytes per recv()")
    parser.add_argument("--interval", type=float, default=0.1, help="sleep between reads (s)")
    parser.add_argument("--seconds", type=float, default=10.0, help="how long to read")
    parser.add_argument("--smoke", action="store_true", help="3 s run; assert send() blocked")
    args = parser.parse_args()
    if not args.smoke:
        run(args.port, args.rcvbuf, args.read_size, args.interval, args.seconds)
        return 0
    sender = run(args.port, 4096, 1024, 0.1, 3.0)
    if sender.longest_block >= 0.2:
        print("smoke: OK, the slow reader closed the window and send() blocked")
        return 0
    print("smoke: FAIL, send() never blocked: flow control did not stop the sender")
    return 1


if __name__ == "__main__":
    sys.exit(main())
