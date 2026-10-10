"""Lesson 0.6 demo: the 0.5 echo server again, written the way runtimes want it.

Same bytes, same port idea as lesson 0.5's epoll server, but no epoll in sight:
asyncio.start_server() hides the listener, the non-blocking fds and the event
loop. Underneath, asyncio's loop is a selectors.EpollSelector (Lib/selectors.py)
calling epoll_wait() in BaseEventLoop._run_once(), and every coroutine parked in
`await reader.read()` is a callback waiting for its fd to become readable.

    python3 main.py                 # serve on 127.0.0.1:9006
    python3 main.py --buf-size 4096 # read in 4 KiB pieces
    python3 main.py --smoke         # 50 concurrent clients, one thread, self-checking
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import os
import sys
import threading

SMOKE_CLIENTS = 50


async def handle(
    reader: asyncio.StreamReader, writer: asyncio.StreamWriter, quiet: bool, buf_size: int
) -> None:
    port = writer.get_extra_info("peername")[1]
    echoed = 0
    while data := await reader.read(buf_size):  # parks this coroutine until the fd is readable
        writer.write(data)  # the transport tries send() at once, buffers what does not fit
        await writer.drain()  # parks again only if that buffer is over its high-water mark
        echoed += len(data)
    writer.close()
    await writer.wait_closed()
    if not quiet:
        print(f"port {port}: echoed {echoed} bytes, closed", flush=True)


async def serve(port: int, quiet: bool, buf_size: int = 65536) -> asyncio.Server:
    server = await asyncio.start_server(
        lambda r, w: handle(r, w, quiet, buf_size), host="127.0.0.1", port=port, reuse_address=True
    )
    selector = type(asyncio.get_running_loop()._selector).__name__  # EpollSelector on Linux
    print(
        f"echo-asyncio: pid {os.getpid()}, listening on 127.0.0.1:{port} "
        f"({selector}, {threading.active_count()} thread)",
        flush=True,
    )
    return server


async def one_client(port: int, number: int) -> bool:
    reader, writer = await asyncio.open_connection("127.0.0.1", port)
    message = f"hello from client {number}\n".encode()
    writer.write(message)
    await writer.drain()
    echoed = await reader.readexactly(len(message))
    writer.close()
    await writer.wait_closed()
    return echoed == message


async def smoke(port: int) -> int:
    server = await serve(port, quiet=True)
    async with server:
        results = await asyncio.gather(*(one_client(port, n) for n in range(SMOKE_CLIENTS)))
    ok = sum(results)
    threads = threading.active_count()
    if ok == SMOKE_CLIENTS:
        print(f"smoke: OK, {ok} concurrent clients echoed by {threads} thread")
        return 0
    print(f"smoke: FAIL, {ok} of {SMOKE_CLIENTS} clients got their echo")
    return 1


async def run_forever(port: int, buf_size: int) -> None:
    server = await serve(port, quiet=False, buf_size=buf_size)
    async with server:
        await server.serve_forever()


def main() -> int:
    parser = argparse.ArgumentParser(description="Echo server on asyncio.")
    parser.add_argument("--port", type=int, default=9006)
    parser.add_argument("--buf-size", type=int, default=65536, help="bytes per read()")
    parser.add_argument("--smoke", action="store_true", help="50 clients, then exit")
    args = parser.parse_args()
    if args.smoke:
        return asyncio.run(smoke(args.port))
    with contextlib.suppress(KeyboardInterrupt):
        asyncio.run(run_forever(args.port, args.buf_size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
