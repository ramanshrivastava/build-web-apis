# Build Web APIs

**Course Overview**
**Ticketing Project**

---

## Table of Contents

1. [What This Course Is For](#what-this-course-is-for)
2. [Prerequisites](#prerequisites)
3. [The Question: What Makes Data Flow?](#the-question-what-makes-data-flow)
4. [Recommended Reading Order](#recommended-reading-order)
5. [Suggested Paths](#suggested-paths)
6. [Conventions Used](#conventions-used)
7. [How to Use This Course](#how-to-use-this-course)
8. [What This Course Does NOT Cover](#what-this-course-does-not-cover)
9. [Cross-References](#cross-references)
10. [Document Maintenance](#document-maintenance)

---

## What This Course Is For

This is a course on web APIs that starts below the packet and ends at multi-region systems. It builds one ticketing service (events, venues, seats, orders, payments) three times, in Python, Go and Rust, and grows it one capability per module.

It is written for developers who:

- Build or call HTTP APIs at work and want to know what actually happens between `requests.get()` and the server's handler
- Have used FastAPI, net/http or axum, and want to know which work the framework does and which work the kernel does
- Need to make an API correct under concurrency (no double-sold seats), fast under load, and observable when it is not
- Want to read the same idea in three runtimes and understand *why* asyncio, goroutines and tokio behave differently on the same `epoll_wait()`

**This is not a quickstart.** Every mechanism is built by hand before a library does it for you: you parse HTTP before using a framework, write a Postgres wire client before using a driver, and build a load balancer before configuring one. Every claim is backed by something you can see: a packet capture, a syscall trace, a socket queue, a lock row or a flamegraph.

---

## Prerequisites

Before starting, you should have:

- **One of Python, Go or Rust at a working level**: you can write functions, read a stack trace and run tests. You will *read* all three; you need to *write* only one.
- **Terminal comfort**: pipes, environment variables, `curl`, `jq`, reading a man page.
- **Basic HTTP vocabulary**: methods, status codes, headers, JSON bodies.
- **Basic SQL**: `SELECT`, `INSERT`, `UPDATE`, a `JOIN`, what a transaction is.
- **Docker installed**: Postgres, Redis and the Linux lab run in containers.

You do **not** need:

- Networking or operating-systems coursework: Module 0 builds the stack from signals on a wire up to syscalls
- Linux as your daily OS: every Linux-only tool runs in the lab container, the same on macOS and in CI
- Prior Go or Rust: Python carries the narrative, and the other two ports follow the same names line by line
- Any framework experience: frameworks arrive in lesson 2.4, after you have built what they replace
- Kubernetes experience: Module 8 maps the app onto Kubernetes and links to a full series for the rest

---

## The Question: What Makes Data Flow?

A network is a flow of data. Every lesson asks the same two-part question at its own layer: **what makes the data flow, and what makes it stop?**

- At the wire, voltage changes and DMA rings move bytes, and a full ring drops them.
- In TCP, the receive window and congestion window pace the sender, and a zero window stops it.
- In the kernel, socket buffers and the accept queue hold data until a process reads it.
- In HTTP, framing (`Content-Length`, chunked encoding, HTTP/2 frames) says where a message ends.
- In the database, locks, version checks and idempotency keys are *deliberate* stops that protect an invariant.
- At the edge, TLS, tokens and rate limits decide who may flow at all.
- Under load, pools and caches are bounded buffers, and their limits are where latency comes from.
- Across machines, load balancers spread the flow, while retries, breakers, deadlines and shedding stop it from amplifying failure.

The first "Key mental model" in every lesson is that module's version of this question, and every diagram marks the places where data flows (`flow`) and where it waits or is refused (`stop`). By the capstone (lesson 8.5), you can follow one `POST /orders` through every buffer and every limit in the stack.

---

## Recommended Reading Order

| Module | Folder | Title | What the app gains | Tag |
|--------|--------|-------|--------------------|-----|
| **0** | [`docs/00-how-bytes-move/`](docs/00-how-bytes-move/00-OVERVIEW.md) | How Bytes Move | Nothing yet: demos and the lab. Signals → frames → IP → TCP → kernel buffers → syscalls → runtimes | `m0` |
| **1** | [`docs/01-http-by-hand/`](docs/01-http-by-hand/00-OVERVIEW.md) | HTTP by Hand | `ticketing rawhttp`: a stdlib-only HTTP/1.1 server serving `GET /events` | `m1` |
| **2** | [`docs/02-rest-done-properly/`](docs/02-rest-done-properly/00-OVERVIEW.md) | REST Done Properly | `ticketing api`: framework-based CRUD on Postgres, beside the raw server | `m2` |
| **3** | [`docs/03-other-api-shapes/`](docs/03-other-api-shapes/00-OVERVIEW.md) | Other API Shapes | GraphQL reads, `ticketing inventory-grpc`, a live seat map, payment webhooks | `m3` |
| **4** | [`docs/04-correct-under-load/`](docs/04-correct-under-load/00-OVERVIEW.md) | Correct Under Load | `POST /orders` with no double sales, idempotency keys, outbox, `ticketing worker` | `m4` |
| **5** | [`docs/05-auth-and-the-edge/`](docs/05-auth-and-the-edge/00-OVERVIEW.md) | Auth and the Edge | TLS, users and sessions, OIDC, API keys, a rate limiter, nginx in front | `m5` |
| **6** | [`docs/06-fast-and-observable/`](docs/06-fast-and-observable/00-OVERVIEW.md) | Fast and Observable | Benchmarks, profiles, tuned pools, caching, logs, metrics, traces, SLOs | `m6` |
| **7** | [`docs/07-distributed-apis/`](docs/07-distributed-apis/00-OVERVIEW.md) | Distributed APIs | `ticketing lb`, shards and replicas, resilience, sagas, a two-region on-sale run | `m7` |
| **8** | [`docs/08-run-it/`](docs/08-run-it/00-OVERVIEW.md) | Run It | Non-root images, Kubernetes on kind, zero-error rollouts, versioning, the capstone | `m8` |

Check out a tag to see the app exactly as a module left it: `git checkout m4`. Compare two modules with `git diff m3 m4 -- apps/python`.

---

## Suggested Paths

### Full Path (recommended)

**Goal**: understand every layer an API request crosses, and build each one.

```
M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7 → M8
│    │    │    │    │    │    │    │    └─ Ship it: containers, k8s, rollouts, the whole picture
│    │    │    │    │    │    │    └─ Many boxes: balancing, sharding, resilience, sagas
│    │    │    │    │    │    └─ Where time goes: benchmarks, profiles, pools, caches, traces
│    │    │    │    │    └─ Who may flow: TLS, identity, OAuth, keys, limits, proxies
│    │    │    │    └─ No double sales: isolation, locks, idempotency, outbox
│    │    │    └─ Other shapes: GraphQL, protobuf, HTTP/2 + gRPC, WebSockets, webhooks, QUIC
│    │    └─ REST semantics, frameworks, Postgres wire protocol
│    └─ HTTP/1.1 by hand: parser, bodies, keep-alive, router, concurrency models
└─ Electrons to syscalls
```

**Time estimate**: about 100 hours (50 lessons at roughly 2 hours each, including running every See It).

### API Engineer Path (you ship APIs at work)

**Goal**: the parts that change how you design, debug and operate production APIs.

```
0.3 → 0.4 → 0.5 → M1 → 2.4 → 2.5 → M4 → 6.1 → 6.3 → 6.6 → 7.4
```

**Time estimate**: 35–40 hours. Read only the `Code:` section of your language if you are short on time; the See Its are language-neutral.

### Runtime Internals Path (how does my language really do I/O?)

**Goal**: follow one read from the NIC to your coroutine, goroutine or future.

```
M0 (all six) → 1.5 → 2.4 → 6.2 → 6.3
```

**Time estimate**: 20–25 hours. Lesson 0.6 is the hinge: the same echo server in asyncio, Go and tokio over the same `epoll_wait()`.

### Correctness and Distribution Path

**Goal**: keep an invariant (one seat, one buyer) true from one Postgres to two regions.

```
2.5 → M4 → 6.3 → 6.6 → M7 → 8.3
```

**Time estimate**: 30–35 hours. Lesson 4.5's stampede test becomes the acceptance test for lesson 7.6's on-sale run.

---

## Conventions Used

### Lesson skeleton

Every lesson follows `docs/LESSON-SKELETON.md`, and `scripts/lint_lessons.py` enforces it in CI. The shape is the same in every lesson: Learning Objectives, *why*, then the mechanism (with a diagram), then `Code: Python`, `Code: Go` and `Code: Rust` in that order, then **See It**, What People Miss, Key Files Summary, Summary, and a checklist.

### See It

Each lesson has exactly one `## K. See It:` section. It shows the exact commands, which tool observes what, and 3–10 lines of real expected output. `just see MM/LL` replays it from `demos/MM/LL/see.sh`, which asserts that a line matching its `EXPECT=` regex appeared. The tool palette and lab setup are in `docs/SEE-IT-TOOLBOX.md`.

### Ticketing example fences

Each numbered section ends by grounding the idea in the app, in a plain fence:

```
TICKETING EXAMPLE: GET /events/42 arrives in two read() calls. The first
returns "GET /events/42 HTTP/1.1\r\nHost: loc"; parse_request_head returns
NeedMore and the connection loop reads again.
```

### Reality checks

Places where common wisdom is wrong, or where a production system bites, are marked like this:

> [!WARNING]
> **Reality check (keepalive-timeouts-race) —** If the server's idle timeout is shorter than the client pool's, the server closes a connection just as the client reuses it, and the request fails with a reset nobody can explain from the logs.

The slug in parentheses names the trap. The exact form matters, because the course site converts these callouts automatically.

### Diagrams

Each lesson has at least one Mermaid diagram, and each module has a rendered hero diagram in `docs/NN-slug/diagrams/`. Nodes name real things (`accept()`, `sk_buff`, `seats.version`), and two accents mark where data flows and where it stops. See `docs/DIAGRAM-STYLE.md`.

### Code order and names

Python first, then Go, then Rust. The same function has the same name in all three (adjusted for casing), so you can read across ports.

### Links

Links inside the course are repo-root-relative (`docs/01-http-by-hand/00-OVERVIEW.md`), never `./` or `../`, so the course site can publish them unchanged.

---

## How to Use This Course

### For each lesson

1. **Read the why and the mechanism.** Do not skip the diagram; it is the map for everything after it.
2. **Run the demo**: `just demo MM/LL python` (then `go`, then `rust`). Demos are single files you can read in one sitting.
3. **See it yourself**: `just lab`, then type the See It commands by hand before running `just see MM/LL`. Compare what you see with the lesson's excerpt. If they differ, find out why; that is usually the most valuable part of the lesson.
4. **Read the code sections.** Start with your strongest language if you like, but Python carries the explanations.
5. **Read the app change**: `git diff` between tags shows exactly what the module added to the service.
6. **Work the checklist.** If you cannot explain an item out loud, reread that section.

### For reference

Each module's `00-OVERVIEW.md` lists its lessons with their demos, See It tools and reality checks. Every lesson's Key Files Summary maps the concept to files in all three ports.

### For knowledge validation

Each lesson ends with "Checklist: What You Should Be Able to Explain". Use the checklists of lessons 0.3, 1.2, 2.5, 4.2, 5.1, 6.3 and 7.4 as interview-style self-tests: each asks you to trace a mechanism end to end.

---

## What This Course Does NOT Cover

- **Frontend and browser rendering**: browsers appear only where they change API behaviour (CORS, cookies, WebSockets, caching).
- **Managed API platforms and serverless**: API-gateway products, FaaS and BaaS. Lesson 5.6 builds the parts a gateway provides, so you can evaluate one.
- **Kubernetes in depth**: Module 8 maps this app onto Kubernetes; the platform itself is taught in the build-ai-agents infra-arch series.
- **Service meshes**: sidecars and mTLS meshes are mentioned where they replace something built here (retries, TLS), but not taught.
- **Formal methods**: no TLA+ or model checking. Correctness is shown with locks you can watch and load tests that try to break the invariant.
- **eBPF tooling in depth**: the course observes with tcpdump, strace, ss, perf and runtime profilers; bpftrace appears at most as an aside.
- **Windows networking**: IOCP is named next to epoll and kqueue in lesson 0.5, and everything else is Linux (in the lab) and macOS.

---

## Cross-References

This course is a sibling of [build-ai-agents](https://github.com/ramanshrivastava/build-ai-agents), and the two link to each other where they overlap:

- **[`infra-arch/01-KUBERNETES-FUNDAMENTALS.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/infra-arch/01-KUBERNETES-FUNDAMENTALS.md)**, **[`05-APP-ON-K8S.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/infra-arch/05-APP-ON-K8S.md)**, **[`10-NGINX-PROXIES-AND-INGRESS.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/infra-arch/10-NGINX-PROXIES-AND-INGRESS.md)**, **[`11-SECURITY-DISCOVERY-AND-WHY-K8S.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/infra-arch/11-SECURITY-DISCOVERY-AND-WHY-K8S.md)**: prerequisites for lesson 8.2. Lesson 5.6 rebuilds what doc 10 configures.
- **[`server-arch/01-SYNC-VS-ASYNC.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/server-arch/01-SYNC-VS-ASYNC.md)** through **[`03-FASTAPI-ASYNC-ARCHITECTURE.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/server-arch/03-FASTAPI-ASYNC-ARCHITECTURE.md)**: the async-server view from the application side. Lessons 0.6, 1.5 and 2.4 go underneath it, to the syscalls.
- **[`infra-arch/14-DOCKER-COMPOSE-REFERENCE.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/infra-arch/14-DOCKER-COMPOSE-REFERENCE.md)**: Compose concepts used by this repo's services and profiles.
- **[`agent-ops/00-OVERVIEW.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/agent-ops/00-OVERVIEW.md)**: the same observability discipline (Module 6) applied to agent systems.

---

## Document Maintenance

These documents reflect:

- **Python** 3.12 with **uv** 0.11; FastAPI/Starlette/uvicorn versions pinned in `apps/python/uv.lock` from Module 2
- **Go** 1.23 as the `go.mod` minimum (the lab image installs go1.23.12; newer toolchains build it unchanged)
- **Rust** stable, edition 2021 (1.97+ at the time of writing), with crates pinned in `apps/rust/Cargo.lock`
- **PostgreSQL** 16 and **Redis** 7 (Docker images `postgres:16`, `redis:7`)
- **Lab**: Ubuntu 24.04 (tcpdump 4.99, strace 6.8, tshark 4.2, perf 6.8). Kernel behaviour comes from the host kernel: Docker Desktop's VM on macOS, the runner's kernel in CI
- **Protocols**: RFC 9110 (HTTP semantics), RFC 9112 (HTTP/1.1), RFC 9113 (HTTP/2), RFC 9114 (HTTP/3), RFC 9000 (QUIC), RFC 8446 (TLS 1.3), RFC 6455 (WebSocket), RFC 9457 (problem details), RFC 6749 + RFC 7636 (OAuth 2.0 + PKCE), RFC 7519 (JWT), W3C Trace Context
- **Tooling**: just 1.21+, lychee 0.24.2 (link check), mermaid-cli 11 (diagram check), golangci-lint v2

Kernel-facing lessons (Module 0, lessons 1.5, 6.2 and 8.2) are the most version-sensitive: field names in `ss -i`, `/proc/net/*` and `nstat` counters change between kernels. Each See It names the kernel it was captured on. Framework lessons (2.4 onward) track the lockfiles; re-run `just see` after a dependency bump.

---

**Next Steps**: start with [`docs/00-how-bytes-move/00-OVERVIEW.md`](docs/00-how-bytes-move/00-OVERVIEW.md) to watch a byte travel, or jump to [`docs/01-http-by-hand/00-OVERVIEW.md`](docs/01-http-by-hand/00-OVERVIEW.md) if you already know the network stack.
