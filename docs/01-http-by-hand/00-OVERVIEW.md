# Module 1: HTTP by Hand

> HTTP/1.1 is text on a TCP stream. Parse it, write it, keep the connection, chunk the body, route the path, then pick a concurrency model and watch where it stalls. App gains `GET /events` with zero libraries.

---

## What this module is

The app's first code: a stdlib-only HTTP/1.1 server in each language, built in five steps. First, parse the request head from a byte stream that arrives in arbitrary pieces. Then frame bodies with `Content-Length` and chunked encoding, keep connections alive across requests with an idle timeout, and route paths to handlers over an in-memory events repository. Finally, serve it with three concurrency models (threads, an event loop, goroutines or tasks) under a slow client.

At tag `m1`, `ticketing rawhttp` answers `GET /events` in all three ports, and keeps answering it in every later tag.

## Why a dedicated module

Frameworks hide exactly the parts that fail in production: partial reads, framing ambiguity (request smuggling), keep-alive races, head-of-line blocking and backpressure from slow clients. Writing the server once by hand turns lesson 2.4 into a comparison ("which of these did FastAPI, net/http and hyper do for me?") rather than an act of faith. The raw server stays runnable beside the framework for the rest of the course.

## The flow question

On a TCP stream, **what tells the receiver where one request ends and the next begins, and what happens when one side reads slower than the other writes?** TCP delivers bytes with no message boundaries, so HTTP's framing (`\r\n\r\n` after the head, `Content-Length` or chunk sizes for the body) is what makes a request flow as a unit. `NeedMore` is the parser saying "stop, wait for more bytes". In lesson 1.5 the stop moves into the kernel: a slow client fills the send buffer, `write()` blocks or returns `EAGAIN`, and each concurrency model pays for that stall differently.

## Lessons

| # | Lesson | Status |
|---|--------|--------|
| 1.1 | Request Line and Headers (`01-REQUEST-LINE-AND-HEADERS.md`) | Planned |
| 1.2 | Bodies: Content-Length and Chunked (`02-BODIES-CONTENT-LENGTH-AND-CHUNKED.md`) | Planned |
| 1.3 | Keep-Alive and Pipelining (`03-KEEP-ALIVE-AND-PIPELINING.md`) | Planned |
| 1.4 | A Tiny Router (`04-A-TINY-ROUTER.md`) | Planned |
| 1.5 | Three Concurrency Models (`05-THREE-CONCURRENCY-MODELS.md`) | Planned |

Status moves `Planned` → `In progress` → `Done`. Lesson files appear in this folder as `NN-TITLE.md` and follow [`docs/LESSON-SKELETON.md`](../LESSON-SKELETON.md).

### 1.1 Request Line and Headers

Parsing the request head from bytes, and why `read()` returns whatever it wants.

- **Demo:** a byte-dump server
- **App:** `rawhttp/parser.*`: `parse_request_head(bytes) -> Request | NeedMore`
- **See It:** `curl --trace-ascii`, `tcpdump -A`, `printf … | nc`, `strace -e read` showing partial heads
- **Diagram:** bytes → parser state machine
- **Reality checks:** `(read-returns-what-it-wants)`, `(headers-are-bytes-not-strings)`

### 1.2 Bodies: Content-Length and Chunked

Two ways to frame a body, and what goes wrong when they disagree.

- **Demo:** `chunky`, one chunk per second
- **App:** `rawhttp/body.*`
- **See It:** `curl --raw`, chunk bytes in tcpdump, Wireshark reassembly, `TCP_NODELAY` via `ss -tni`
- **Diagram:** Content-Length vs Transfer-Encoding framing
- **Reality checks:** `(smuggling-is-a-framing-bug)`, `(chunked-is-not-streaming-for-free)`

### 1.3 Keep-Alive and Pipelining

Reusing a connection, idle timeouts, and HTTP/1.1's head-of-line blocking.

- **Demo:** three requests on one socket
- **App:** `rawhttp/conn.*`, `rawhttp/server.*` (accept loop + idle timeout)
- **See It:** `ss -tnp` across two curls, no new SYN, `strace -e accept4,close`
- **Diagram:** the connection lifecycle
- **Reality checks:** `(keepalive-timeouts-race)`, `(head-of-line-blocking-is-h1)`

### 1.4 A Tiny Router

Matching paths to handlers, 405 vs 404, and the first domain type.

- **Demo:** a 40-line matcher
- **App:** `rawhttp/router.*`, `domain/event.*` (in-memory repository), `rawhttp/handlers.*`, tests
- **See It:** `curl -i /events/42`, `strace -c`, VmRSS with 10k events
- **Diagram:** request → router → handler → bytes
- **Reality checks:** `(405-not-404)`, `(json-is-not-free)`

### 1.5 Three Concurrency Models

Threads, an event loop, goroutines and tasks; slow-client backpressure.

- **Demo:** a slowloris client and three servers per language
- **App:** `rawhttp --model threads|loop`; tag `m1`
- **See It:** `wrk --latency`, Send-Q growth, blocked `write()` vs `EAGAIN`, `py-spy dump`, `GODEBUG=schedtrace`, `tokio-console`, `/proc/<pid>/status Threads:`
- **Diagram:** the three models side by side
- **Reality checks:** `(backpressure-is-a-full-buffer)`, `(event-loops-block-too)`

## What this module does NOT cover

- **HTTP/2 and HTTP/3**: Module 3 (lessons 3.3 and 3.6).
- **TLS**: lesson 5.1. Everything in this module is plaintext on localhost.
- **Frameworks**: lesson 2.4 maps FastAPI, net/http + chi and axum onto this module's server.
- **HTTP caching semantics**: lesson 6.4.
- **Full RFC 9112 compliance**: the parser handles what the lessons need and rejects the rest with `400`; it is a teaching server, not a hardened one.

## Cross-references

- **Previous module:** [`docs/00-how-bytes-move/00-OVERVIEW.md`](../00-how-bytes-move/00-OVERVIEW.md) explains the sockets, buffers and syscalls this server sits on.
- **Next module:** [`docs/02-rest-done-properly/00-OVERVIEW.md`](../02-rest-done-properly/00-OVERVIEW.md) puts REST semantics and a framework on top, and keeps `rawhttp` running beside it.
- **Module gate:** M1: stdlib only, no frameworks or HTTP libraries in any port. See [`CLAUDE.md`](../../CLAUDE.md), "Module Gates".
- **Design spec:** [`docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`](../superpowers/specs/2026-10-10-build-web-apis-course-design.md) has the binding conventions and this module's full lesson plan.

## Status

Module overview stub, written in Phase 0. All 5 lessons (1.1–1.5) are planned and none are written yet. The module lands as one PR from branch `module/01-http-by-hand` and is tagged `m1` when the definition of done in [`CONTRIBUTING.md`](../../CONTRIBUTING.md) passes. The hero diagram (`diagrams/hero.mmd`, rendered to `.excalidraw`, `.svg` and `.png`) is drawn with the module and embedded under the thesis once the first lesson is `Done`.
