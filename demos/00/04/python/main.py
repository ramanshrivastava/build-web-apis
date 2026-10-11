"""Lesson 0.4 demo: neveraccept, a server that listens and never calls accept().

The kernel completes TCP handshakes without the process: a finished connection
waits in the listener's accept queue until accept() takes it. With nobody
calling accept(), the queue fills (Linux holds backlog + 1), and from then on
the kernel drops new SYNs, so later clients sit in SYN_SENT and retransmit.
With --drain the server finally accepts, closes each connection first (so its
side lands in TIME_WAIT) and lets the retransmitted SYNs in. Linux only.

    python3 main.py                     # backlog 4, 8 clients, hold 30 s for ss
    python3 main.py --hold 5 --drain    # then accept everything and close it
    python3 main.py --smoke             # assert 5 connected, 3 pending, then all 8 drained
"""

from __future__ import annotations

import argparse
import errno
import select
import socket
import sys
import time


def listen(port: int, backlog: int) -> socket.socket:
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    # TIME_WAIT sockets from a previous --drain still hold the port; allow rebinding.
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", port))
    listener.listen(backlog)  # the accept queue's limit (capped by net.core.somaxconn)
    return listener


def start_clients(port: int, count: int) -> list[socket.socket]:
    clients = []
    for _ in range(count):
        client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client.setblocking(False)  # connect() returns at once; the handshake goes on
        code = client.connect_ex(("127.0.0.1", port))
        if code not in (0, errno.EINPROGRESS):
            raise OSError(code, f"connect: {errno.errorcode.get(code, code)}")
        clients.append(client)
    return clients


def connected(client: socket.socket) -> bool:
    """A non-blocking connect has finished when the socket is writable with SO_ERROR 0."""
    poller = select.poll()
    poller.register(client, select.POLLOUT)
    if not poller.poll(0):
        return False
    return client.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR) == 0


def report(clients: list[socket.socket], backlog: int) -> int:
    done = 0
    for number, client in enumerate(clients, 1):
        port = client.getsockname()[1]
        if connected(client):
            done += 1
            print(f"client {number}: connected from port {port} (waiting in the accept queue)")
        else:
            print(f"client {number}: pending from port {port} (SYN_SENT: no SYN-ACK yet)")
    print(
        f"result: {done} connected, {len(clients) - done} pending; "
        f"the accept queue holds backlog+1 = {backlog + 1}"
    )
    return done


def drain(listener: socket.socket, expected: int, seconds: float) -> int:
    """Accept for up to `seconds`, closing each connection server-side first."""
    listener.setblocking(False)
    accepted, started = 0, time.monotonic()
    while accepted < expected and (elapsed := time.monotonic() - started) < seconds:
        try:
            conn, peer = listener.accept()
        except BlockingIOError:
            time.sleep(0.05)  # queue empty; a retransmitted SYN may still arrive
            continue
        accepted += 1
        print(f"drain: accept() -> fd {conn.fileno()} from port {peer[1]} at +{elapsed:.1f} s")
        conn.close()  # the server closes first, so the server side goes to TIME_WAIT
    print(f"drain: accepted {accepted}; closed first, so they sit in TIME_WAIT (60 s)")
    return accepted


def run(port: int, backlog: int, count: int, hold: float, do_drain: bool) -> tuple[int, int]:
    listener = listen(port, backlog)
    print(f"neveraccept: listening on 127.0.0.1:{port}, backlog {backlog}; accept() is not called")
    clients = start_clients(port, count)
    time.sleep(0.5)  # let the handshakes that can complete, complete
    done = report(clients, backlog)
    if hold > 0:
        print(f"holding {hold:g} s: try  ss -lnt 'sport = :{port}'", flush=True)
        time.sleep(hold)
    drained = drain(listener, count, seconds=4.0) if do_drain else 0
    for client in clients:
        client.close()
    listener.close()
    return done, drained


def main() -> int:
    parser = argparse.ArgumentParser(description="Listen, never accept, watch the queue fill.")
    parser.add_argument("--port", type=int, default=9004)
    parser.add_argument("--backlog", type=int, default=4, help="listen() backlog")
    parser.add_argument("--clients", type=int, default=8, help="connections to attempt")
    parser.add_argument("--hold", type=float, default=30.0, help="seconds to wait before exit")
    parser.add_argument("--drain", action="store_true", help="then accept and close everything")
    parser.add_argument("--smoke", action="store_true", help="assert the Linux queue numbers")
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        print("neveraccept: the backlog+1 rule is Linux's; run it in the lab: just demo 00/04")
        return 2
    if not args.smoke:
        run(args.port, args.backlog, args.clients, args.hold, args.drain)
        return 0
    done, drained = run(args.port, 4, 8, hold=0, do_drain=True)
    if done == 5 and drained == 8:
        print("smoke: OK, 5 waited in the accept queue, 3 were dropped, all 8 drained")
        return 0
    print(f"smoke: FAIL, expected 5 connected and 8 drained, got {done} and {drained}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
