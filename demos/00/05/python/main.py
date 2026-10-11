"""Lesson 0.5 demo: an echo server two ways, blocking and with raw epoll.

--mode blocking: socket(), bind(), listen(), then accept() and read()/write()
one client at a time. While it is blocked in read() on client A, client B's
connection waits in the accept queue: head-of-line blocking.

--mode epoll: every fd is O_NONBLOCK and one epoll instance says which fds are
ready. read() returns EAGAIN when a socket is drained; that is the signal to go
back to epoll_wait(), not an error. One thread serves every client.

Each line the server prints names the syscall it just made, so the output
lines up with `strace -e trace=%net,read,write,close,/^epoll`. Linux only.

    python3 main.py --mode blocking      # serve on 127.0.0.1:9005
    python3 main.py --mode epoll
    python3 main.py --smoke              # both modes, two clients each, self-checking
"""

from __future__ import annotations

import argparse
import errno
import os
import select
import socket
import sys
import threading
import time

BACKLOG = 16


def make_listener(port: int, nonblocking: bool) -> socket.socket:
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)  # socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", port))  # bind()
    listener.listen(BACKLOG)  # listen()
    if nonblocking:
        os.set_blocking(listener.fileno(), False)  # O_NONBLOCK (CPython: ioctl FIONBIO)
    return listener


def serve_blocking(listener: socket.socket, max_clients: int) -> None:
    port = listener.getsockname()[1]
    print(
        f"echo-blocking: pid {os.getpid()}, listening fd {listener.fileno()} on {port}", flush=True
    )
    served = 0
    while max_clients == 0 or served < max_clients:
        conn, peer = listener.accept()  # blocks until the accept queue is non-empty
        fd = conn.fileno()
        print(f"accept() = fd {fd} from port {peer[1]}", flush=True)
        while True:
            data = os.read(fd, 65536)  # blocks until bytes arrive or the peer closes
            print(f"read({fd}) = {len(data)}", flush=True)
            if not data:
                break
            sent = 0
            while sent < len(data):  # write() may take fewer bytes than asked: send the rest
                n = os.write(fd, data[sent:])  # blocks while the send buffer is full
                print(f"write({fd}) = {n}", flush=True)
                sent += n
        conn.close()
        print(f"close({fd})", flush=True)
        served += 1


def serve_epoll(listener: socket.socket, max_clients: int) -> None:
    epoll = select.epoll()  # epoll_create1(EPOLL_CLOEXEC)
    lfd = listener.fileno()
    epoll.register(lfd, select.EPOLLIN)  # epoll_ctl(EPOLL_CTL_ADD)
    print(
        f"echo-epoll: pid {os.getpid()}, listening fd {lfd} on {listener.getsockname()[1]}, "
        f"epoll fd {epoll.fileno()}",
        flush=True,
    )
    conns: dict[int, socket.socket] = {}  # keep the socket objects alive
    pending: dict[int, bytes] = {}  # bytes read but not yet written back: the loop owes them
    served = 0
    try:
        while max_clients == 0 or served < max_clients:
            events = epoll.poll()  # epoll_wait(): sleep until some fd is ready
            ready = ", ".join(f"fd {fd}" for fd, _ in events)
            print(f"epoll_wait() = {len(events)} ready: {ready}", flush=True)
            for fd, _ in events:
                if fd == lfd:
                    accept_all(listener, epoll, conns)
                    continue
                try:
                    if fd in pending:  # it watches EPOLLOUT until we have written what we owe
                        closed = flush_pending(fd, pending, epoll)
                    else:
                        closed = echo_until_eagain(fd, pending, epoll)
                except (ConnectionResetError, BrokenPipeError) as err:
                    name = errno.errorcode.get(err.errno or 0, err.errno)
                    print(f"fd {fd}: {name} ({err.strerror}); closing", flush=True)
                    closed = True
                if closed:
                    epoll.unregister(fd)
                    pending.pop(fd, None)
                    conns.pop(fd).close()
                    print(f"close({fd})", flush=True)
                    served += 1
    finally:
        for conn in conns.values():  # a client still connected when the loop ends
            conn.close()
        epoll.close()


def accept_all(listener: socket.socket, epoll: select.epoll, conns: dict) -> None:
    while True:
        try:
            conn, peer = listener.accept()
        except BlockingIOError:
            print("accept() = EAGAIN (accept queue empty)", flush=True)
            return
        except OSError as err:
            if err.errno != errno.EMFILE:
                raise
            # No fd left: the connection stays queued, the listener stays readable,
            # and level-triggered epoll would wake us again at once. Back off.
            print("accept() = EMFILE (no free fd; the connection stays queued)", flush=True)
            time.sleep(1.0)
            return
        fd = conn.fileno()
        try:
            os.set_blocking(fd, False)
            epoll.register(fd, select.EPOLLIN)
        except OSError:
            conn.close()  # never leak an accepted fd we failed to set up
            raise
        conns[fd] = conn
        print(f"accept() = fd {fd} from port {peer[1]}, O_NONBLOCK, added to epoll", flush=True)


def echo_until_eagain(fd: int, pending: dict[int, bytes], epoll: select.epoll) -> bool:
    """Echo everything readable on fd; True when the peer has closed."""
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            print(f"read({fd}) = EAGAIN (drained; back to epoll_wait)", flush=True)
            return False
        print(f"read({fd}) = {len(data)}", flush=True)
        if not data:
            return True
        if not write_or_keep(fd, data, pending, epoll):
            return False  # the send buffer is full: stop reading until EPOLLOUT


def write_or_keep(fd: int, data: bytes, pending: dict[int, bytes], epoll: select.epoll) -> bool:
    """Write data; keep what the send buffer refuses in pending[fd]. True if all of it went."""
    try:
        sent = os.write(fd, data)  # may take only part of data, or nothing (EAGAIN)
    except BlockingIOError:
        sent = 0
    if sent == len(data):
        print(f"write({fd}) = {sent}", flush=True)
        return True
    pending[fd] = data[sent:]
    # Watch EPOLLOUT instead of EPOLLIN: wake when the send buffer has room, and read
    # nothing more from this client until it has taken what we already owe it.
    epoll.modify(fd, select.EPOLLOUT)
    result = f"{sent} (short write" if sent else "EAGAIN (send buffer full"
    print(
        f"write({fd}) = {result}: {len(pending[fd])} bytes pending, waiting for EPOLLOUT)",
        flush=True,
    )
    return False


def flush_pending(fd: int, pending: dict[int, bytes], epoll: select.epoll) -> bool:
    """EPOLLOUT fired: write what we owe; once it is all gone, read the client again."""
    if write_or_keep(fd, pending.pop(fd), pending, epoll):
        epoll.modify(fd, select.EPOLLIN)
        print(f"epoll_ctl(MOD, fd {fd}, EPOLLIN): output drained, reading again", flush=True)
    return False


def wait_echo(client: socket.socket, message: bytes, timeout: float) -> bool:
    """Did `message` come back within `timeout` seconds?"""
    client.settimeout(timeout)
    try:
        return client.recv(65536) == message
    except TimeoutError:
        return False


def echo_once(client: socket.socket, message: bytes, timeout: float) -> bool:
    client.sendall(message)
    return wait_echo(client, message, timeout)


def smoke_mode(mode: str, port: int) -> bool:
    listener = make_listener(port, nonblocking=(mode == "epoll"))
    serve = serve_blocking if mode == "blocking" else serve_epoll
    server = threading.Thread(target=serve, args=(listener, 2), daemon=True)
    server.start()
    a = socket.create_connection(("127.0.0.1", port))
    b = socket.create_connection(("127.0.0.1", port))
    a_ok = echo_once(a, b"hello from A\n", 1.0)
    b_early = echo_once(b, b"hello from B\n", 0.5)  # while A is still connected
    a.close()
    b_late = b_early or wait_echo(b, b"hello from B\n", 1.0)
    b.close()
    server.join(timeout=2.0)
    listener.close()
    time.sleep(0.1)
    if mode == "blocking":
        ok = a_ok and not b_early and b_late
        print(f"smoke: blocking: B echoed only after A hung up: {ok}")
    else:
        ok = a_ok and b_early
        print(f"smoke: epoll: B echoed while A was still connected: {ok}")
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description="Echo server: blocking vs raw epoll.")
    parser.add_argument("--mode", choices=["blocking", "epoll"], default="epoll")
    parser.add_argument("--port", type=int, default=9005)
    parser.add_argument("--max-clients", type=int, default=0, help="exit after N (0: forever)")
    parser.add_argument("--smoke", action="store_true", help="test both modes and exit")
    args = parser.parse_args()
    if not hasattr(select, "epoll"):
        print("echo: epoll is Linux-only; run it in the lab: just demo 00/05 python")
        return 2
    if args.smoke:
        results = [smoke_mode("blocking", args.port), smoke_mode("epoll", args.port)]
        print("smoke: OK" if all(results) else "smoke: FAIL")
        return 0 if all(results) else 1
    listener = make_listener(args.port, nonblocking=(args.mode == "epoll"))
    try:
        if args.mode == "blocking":
            serve_blocking(listener, args.max_clients)
        else:
            serve_epoll(listener, args.max_clients)
    except KeyboardInterrupt:
        pass
    except OSError as err:
        print(f"echo: {errno.errorcode.get(err.errno or 0, err.errno)} ({err.strerror})")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
