# Build Web APIs

> Learn to build web APIs from electrons to distributed systems — by building a real ticketing service three times, in Python, Go and Rust.

This repo is a structured learning path that starts below the packet and ends at multi-region APIs. One question runs through every lesson: **a network is a flow of data, so what makes it flow, and what makes it stop?** Signals and DMA rings move bytes, TCP windows pace them, socket buffers hold them, parsers frame them, locks and rate limits deliberately stop them, and load balancers spread them. Every lesson has one rule: **see the internals**. Nothing is described that the lesson does not also show with a real tool, whether that is `tcpdump`, `strace`, `ss`, `pg_locks`, a profiler or a trace waterfall. Each lesson has a reproducible `just see` command, and you build every layer by hand before a library does it for you.

Each module adds one capability to the same ticketing service (events, venues, seats, orders, payments). Within a module, Python carries the narrative, then the Go and Rust ports follow, with the same names and the same subcommands. Old code paths stay runnable, so "the raw server and the framework, side by side" is something you can run, not just read about.

---

## Syllabus

### Module 0: How Bytes Move

> Before you write an API, watch a byte travel: physics moves it, framing bounds it, addressing directs it, windows pace it, buffers hold it.

| Resource | What You'll Learn |
|----------|-------------------|
| [`docs/00-how-bytes-move/00-OVERVIEW.md`](docs/00-how-bytes-move/00-OVERVIEW.md) | Module overview, lesson outline, the flow question at the physical layer |
| `docs/00-how-bytes-move/01-ELECTRONS-TO-FRAMES.md` | *Planned* — signals, NIC, DMA rings, interrupts and NAPI, Ethernet frames, MTU |
| `docs/00-how-bytes-move/02-ADDRESSING-AND-ROUTING.md` | *Planned* — IP, ARP, routing tables, NAT as state, DNS over UDP by hand |
| `docs/00-how-bytes-move/03-TCP-FLOW-AND-CONGESTION.md` | *Planned* — handshake, seq/ack, receive window, Nagle and delayed ACK, cwnd, CUBIC and BBR |
| `docs/00-how-bytes-move/04-KERNEL-STACK-AND-BUFFERS.md` | *Planned* — `sk_buff`, socket buffers, SYN backlog vs accept queue, SYN cookies, TIME_WAIT |
| `docs/00-how-bytes-move/05-SOCKET-SYSCALLS.md` | *Planned* — socket/bind/listen/accept, file descriptors, `O_NONBLOCK`, select/poll/epoll/kqueue |
| `docs/00-how-bytes-move/06-HOW-RUNTIMES-WRAP-SYSCALLS.md` | *Planned* — CPython `socketmodule.c` and `selectors`, Go's netpoller, mio and tokio |
| [`scripts/capture/`](scripts/capture/) | **Live code** — `tcpdump`, `strace` and `ss` capture wrappers used by every See It |
| [`scripts/see/common.sh`](scripts/see/common.sh) | **Live code** — helpers every `see.sh` uses (`require_tool`, `expect_match`) |
| [`infra/lab/Dockerfile`](infra/lab/Dockerfile) | **Live code** — the Linux lab: the whole See It palette plus three toolchains |

### Module 1: HTTP by Hand

> HTTP/1.1 is text on a TCP stream. Parse it, write it, keep the connection, chunk the body, route the path, then pick a concurrency model and watch where it stalls. The app gains `GET /events` with zero libraries.

| Resource | What You'll Learn |
|----------|-------------------|
| [`docs/01-http-by-hand/00-OVERVIEW.md`](docs/01-http-by-hand/00-OVERVIEW.md) | Module overview, lesson outline, the flow question on a TCP stream |
| `docs/01-http-by-hand/01-REQUEST-LINE-AND-HEADERS.md` | *Planned* — a byte-level request parser that handles partial reads (`NeedMore`) |
| `docs/01-http-by-hand/02-BODIES-CONTENT-LENGTH-AND-CHUNKED.md` | *Planned* — Content-Length vs chunked framing, and why smuggling is a framing bug |
| `docs/01-http-by-hand/03-KEEP-ALIVE-AND-PIPELINING.md` | *Planned* — connection reuse, idle timeouts, head-of-line blocking in HTTP/1.1 |
| `docs/01-http-by-hand/04-A-TINY-ROUTER.md` | *Planned* — a 40-line path matcher, 405 vs 404, the in-memory events repository |
| `docs/01-http-by-hand/05-THREE-CONCURRENCY-MODELS.md` | *Planned* — threads, event loop, goroutines and tasks under a slowloris client |
| `rawhttp/` in [`apps/python`](apps/python/src/ticketing/) · [`apps/go`](apps/go/internal/) · [`apps/rust`](apps/rust/src/) | **Live code** — *Planned* — parser, bodies, connection loop, router; `ticketing rawhttp` (tag `m1`) |

### Module 2: REST Done Properly

> REST is constraints about resources and representations, not JSON over POST. Get the semantics right by hand, then let a framework do the plumbing, knowing exactly which plumbing. The app gains CRUD on Postgres.

| Resource | What You'll Learn |
|----------|-------------------|
| [`docs/02-rest-done-properly/00-OVERVIEW.md`](docs/02-rest-done-properly/00-OVERVIEW.md) | Module overview, lesson outline, the flow question through a framework |
| `docs/02-rest-done-properly/01-RESOURCES-METHODS-AND-IDEMPOTENCY.md` | *Planned* — resources, method semantics, safe vs idempotent, replaying POST and PUT |
| `docs/02-rest-done-properly/02-PAGINATION-ETAGS-AND-CONDITIONAL-REQUESTS.md` | *Planned* — keyset pagination, ETags, `304 Not Modified` with zero body bytes |
| `docs/02-rest-done-properly/03-ERRORS-RFC-9457-AND-OPENAPI.md` | *Planned* — problem+json errors, a hand-written `openapi/ticketing.yaml` |
| `docs/02-rest-done-properly/04-FRAMEWORKS-AND-WHAT-THEY-DO-FOR-YOU.md` | *Planned* — FastAPI, net/http + chi and axum, each mapped onto Module 1's raw server |
| `docs/02-rest-done-properly/05-POSTGRES-AND-THE-WIRE-PROTOCOL.md` | *Planned* — Parse/Bind/Execute, prepared statements, drivers, plain-SQL migrations |
| `api/`, `domain/`, `store/` in [`apps/python`](apps/python/src/ticketing/) · [`apps/go`](apps/go/internal/) · [`apps/rust`](apps/rust/src/) | **Live code** — *Planned* — framework API beside the raw server; `ticketing api` (tag `m2`) |
| [`db/migrations/`](db/migrations/) | **Live code** — *Planned* — `0001_init.sql`, `0002_seed.sql`, applied by [`scripts/migrate.sh`](scripts/migrate.sh) |

### Module 3: Other API Shapes

> REST is one shape. Build the others small enough to see through. The app gains nested reads, an inventory service over gRPC, a live seat map and payment callbacks.

| Resource | What You'll Learn |
|----------|-------------------|
| [`docs/03-other-api-shapes/00-OVERVIEW.md`](docs/03-other-api-shapes/00-OVERVIEW.md) | Module overview, lesson outline, the flow question for streams and pushes |
| `docs/03-other-api-shapes/01-GRAPHQL-EXECUTOR-BY-HAND.md` | *Planned* — a 150-line GraphQL parser and executor, N+1 queries and the dataloader |
| `docs/03-other-api-shapes/02-PROTOBUF-WIRE-FORMAT.md` | *Planned* — varints and tags by hand, compared byte for byte with generated code |
| `docs/03-other-api-shapes/03-HTTP2-FRAMING-AND-GRPC.md` | *Planned* — frames, HPACK, streams, flow-control windows, gRPC framing and trailers |
| `docs/03-other-api-shapes/04-WEBSOCKETS-AND-SSE.md` | *Planned* — the upgrade handshake by hand, frames and masking, server-sent events |
| `docs/03-other-api-shapes/05-WEBHOOKS.md` | *Planned* — HMAC signatures, replay windows, retries with backoff, idempotent receivers |
| `docs/03-other-api-shapes/06-HTTP3-AND-QUIC.md` | *Planned* — QUIC streams over UDP, handshake latency, when HTTP/3 does not help |
| `graphql/`, `inventory/`, `live/`, `webhooks/` in [`apps/python`](apps/python/src/ticketing/) · [`apps/go`](apps/go/internal/) · [`apps/rust`](apps/rust/src/) | **Live code** — *Planned* — `ticketing inventory-grpc`, seat-status stream, payment webhooks (tag `m3`) |

### Module 4: Correct Under Load

> Two people must not buy the same seat. Correctness comes from the database's locks, version columns, idempotency keys and an outbox, and you can watch every one of them in `pg_locks`.

| Resource | What You'll Learn |
|----------|-------------------|
| [`docs/04-correct-under-load/00-OVERVIEW.md`](docs/04-correct-under-load/00-OVERVIEW.md) | Module overview, lesson outline, the flow question when writers collide |
| `docs/04-correct-under-load/01-TRANSACTIONS-AND-ISOLATION-LEVELS.md` | *Planned* — MVCC snapshots, lost updates at Read Committed, `40001` at Serializable |
| `docs/04-correct-under-load/02-THE-DOUBLE-SELL-PROBLEM.md` | *Planned* — `FOR UPDATE` vs optimistic versions vs a partial unique index; seat holds |
| `docs/04-correct-under-load/03-IDEMPOTENCY-KEYS.md` | *Planned* — idempotency middleware with request fingerprints, retries after timeouts |
| `docs/04-correct-under-load/04-OUTBOX-AND-BACKGROUND-JOBS.md` | *Planned* — the dual-write problem, the outbox, `SKIP LOCKED`, Redis Streams workers |
| `docs/04-correct-under-load/05-PROVING-IT-A-STAMPEDE-TEST.md` | *Planned* — a load harness that asserts zero double sales, run in CI |
| `store/`, `outbox/`, `worker/` in [`apps/python`](apps/python/src/ticketing/) · [`apps/go`](apps/go/internal/) · [`apps/rust`](apps/rust/src/) | **Live code** — *Planned* — `POST /orders`, idempotency middleware, `ticketing worker` (tag `m4`) |

### Module 5: Auth and the Edge

> Trust is established at the edge: TLS proves the server, tokens prove the caller, rate limits decide who may flow, and a reverse proxy enforces it first. The app gains users, API keys and nginx in front.

| Resource | What You'll Learn |
|----------|-------------------|
| [`docs/05-auth-and-the-edge/00-OVERVIEW.md`](docs/05-auth-and-the-edge/00-OVERVIEW.md) | Module overview, lesson outline, the flow question at the gate |
| `docs/05-auth-and-the-edge/01-TLS-HANDSHAKE.md` | *Planned* — TLS 1.3 handshake, SNI in the clear, decrypting captures with `SSLKEYLOGFILE` |
| `docs/05-auth-and-the-edge/02-IDENTITY-SESSIONS-AND-JWT.md` | *Planned* — password hashing, cookie sessions in Redis, a JWT by hand |
| `docs/05-auth-and-the-edge/03-OAUTH2-AND-OIDC.md` | *Planned* — authorization code flow with PKCE, JWKS and key rotation, a local `dex` |
| `docs/05-auth-and-the-edge/04-API-KEYS-AND-CORS.md` | *Planned* — API keys stored like passwords, CORS preflights, and why CORS is not security |
| `docs/05-auth-and-the-edge/05-RATE-LIMITING-BY-HAND.md` | *Planned* — token and leaky buckets, sliding windows, `429` + `Retry-After`, a Redis Lua limiter |
| `docs/05-auth-and-the-edge/06-REVERSE-PROXIES-AND-API-GATEWAYS.md` | *Planned* — nginx in front of the app: two TCP connections per request, trusted `X-Forwarded-For` |
| `auth/`, `ratelimit/` in [`apps/python`](apps/python/src/ticketing/) · [`apps/go`](apps/go/internal/) · [`apps/rust`](apps/rust/src/) | **Live code** — *Planned* — `api --tls`, sessions, OIDC, API keys, limiter (tag `m5`) |
| [`infra/nginx/`](infra/nginx/) · [`scripts/certs.sh`](scripts/certs.sh) | **Live code** — local TLS certificates now; nginx config *Planned* (compose profile `edge`) |

### Module 6: Fast and Observable

> You cannot make it fast until you can see where time goes. Measure honestly, profile all three runtimes, size the pools, cache what repeats, and emit logs, metrics and traces that answer "why was this request slow?"

| Resource | What You'll Learn |
|----------|-------------------|
| [`docs/06-fast-and-observable/00-OVERVIEW.md`](docs/06-fast-and-observable/00-OVERVIEW.md) | Module overview, lesson outline, the flow question as queueing |
| `docs/06-fast-and-observable/01-BENCHMARKING-HONESTLY.md` | *Planned* — percentiles, coordinated omission, open vs closed load generators |
| `docs/06-fast-and-observable/02-PROFILING-THREE-RUNTIMES.md` | *Planned* — `py-spy`, `pprof` and `go tool trace`, `perf` flamegraphs, the GC in your p99 |
| `docs/06-fast-and-observable/03-CONNECTION-POOLS.md` | *Planned* — Little's law, pool exhaustion as backpressure, pgbouncer |
| `docs/06-fast-and-observable/04-CACHING-AND-COMPRESSION.md` | *Planned* — cache-aside, single-flight, HTTP caching, gzip/br/zstd and when they lose |
| `docs/06-fast-and-observable/05-STRUCTURED-LOGS-AND-METRICS.md` | *Planned* — a hand-rolled histogram and `/metrics`, label cardinality, Prometheus |
| `docs/06-fast-and-observable/06-TRACING-AND-SLOS.md` | *Planned* — `traceparent` by hand across services, OpenTelemetry, Jaeger, SLOs |
| `cache/`, `observability/` in [`apps/python`](apps/python/src/ticketing/) · [`apps/go`](apps/go/internal/) · [`apps/rust`](apps/rust/src/) | **Live code** — *Planned* — pprof/py-spy hooks, metrics, tracing, benchmark scripts (tag `m6`) |

### Module 7: Distributed APIs

> One box is not enough for on-sale day. Spread the flow across boxes and regions without losing the seat invariant.

| Resource | What You'll Learn |
|----------|-------------------|
| [`docs/07-distributed-apis/00-OVERVIEW.md`](docs/07-distributed-apis/00-OVERVIEW.md) | Module overview, lesson outline, the flow question across boxes |
| `docs/07-distributed-apis/01-L7-LOAD-BALANCER-BY-HAND.md` | *Planned* — a 200-line L7 balancer with health checks and upstream keep-alive |
| `docs/07-distributed-apis/02-SERVICE-DISCOVERY-AND-CONSISTENT-HASHING.md` | *Planned* — DNS-based discovery, TTLs, a hash ring with virtual nodes |
| `docs/07-distributed-apis/03-SHARDING-AND-REPLICATION.md` | *Planned* — sharding seats by event, streaming replicas, replica lag as a correctness bug |
| `docs/07-distributed-apis/04-RETRIES-TIMEOUTS-CIRCUIT-BREAKERS-DEADLINES.md` | *Planned* — retry budgets, jitter, breakers, deadline propagation, load shedding |
| `docs/07-distributed-apis/05-SAGAS.md` | *Planned* — hold, charge, confirm: compensations and a persisted state machine |
| `docs/07-distributed-apis/06-ON-SALE-DAY-AND-MULTI-REGION.md` | *Planned* — two regions, failover, and the on-sale run with chaos and zero double sales |
| `lb/`, `resilience/`, `sagas/` in [`apps/python`](apps/python/src/ticketing/) · [`apps/go`](apps/go/internal/) · [`apps/rust`](apps/rust/src/) | **Live code** — *Planned* — `ticketing lb`, shard router, breakers, order saga (tag `m7`) |

### Module 8: Run It

> Shipping is a flow problem too. Kubernetes itself is taught in `build-ai-agents/docs/infra-arch`; here we map this app onto it.

| Resource | What You'll Learn |
|----------|-------------------|
| [`docs/08-run-it/00-OVERVIEW.md`](docs/08-run-it/00-OVERVIEW.md) | Module overview, lesson outline, the flow question during a deploy |
| `docs/08-run-it/01-CONTAINERS-FOR-THREE-RUNTIMES.md` | *Planned* — multi-stage images, namespaces and cgroups, a 40-line container with `unshare` |
| `docs/08-run-it/02-KUBERNETES-FOR-THIS-APP.md` | *Planned* — the app on `kind`: a Service is iptables rules, not a proxy |
| `docs/08-run-it/03-ROLLING-DEPLOYS-AND-GRACEFUL-SHUTDOWN.md` | *Planned* — SIGTERM, draining, readiness vs liveness, a zero-error rollout as a test |
| `docs/08-run-it/04-API-VERSIONING-AND-DEPRECATION.md` | *Planned* — URL vs header vs media-type versions, `Deprecation`/`Sunset`, an `oasdiff` CI gate |
| `docs/08-run-it/05-THE-WHOLE-PICTURE.md` | *Planned* — capstone: one `POST /orders` traced through every layer the course built |
| `infra/k8s/` · `apps/*/Dockerfile` | **Live code** — *Planned* — three non-root images, kind overlays, `scripts/trace-everything.sh` (tag `m8`) |

### Not Covered (Explore on Your Own)

- **Frontend and browser rendering**: the course stops at the API boundary. Browsers appear only where they change API behaviour (CORS, cookies, WebSockets).
- **Managed API platforms**: API gateways-as-a-service, serverless functions and BaaS products. Lesson 5.6 shows what a gateway does by building the parts.
- **Kubernetes in depth**: see the [build-ai-agents infra-arch series](https://github.com/ramanshrivastava/build-ai-agents/tree/main/docs/infra-arch).

The full reading guide, prerequisites and suggested paths are in [`docs/COURSE-OVERVIEW.md`](docs/COURSE-OVERVIEW.md).

---

## Quick Start

### Prerequisites

- Docker (Compose v2) for Postgres, Redis and the Linux lab
- [just](https://just.systems) as the task runner
- Python 3.12+ and [uv](https://docs.astral.sh/uv/)
- Go 1.23+
- Rust stable via [rustup](https://rustup.rs) (with `clippy` and `rustfmt`)
- Optional: `psql` on your host (otherwise run `just migrate` inside `just lab`)

### Run

```bash
just up                      # postgres 16 + redis 7, waits until healthy
just migrate                 # apply db/migrations/*.sql
just test                    # pytest, go test -race, cargo test
just demo 01/01 python       # run a lesson's demo (from Module 1 on)
just see 01/01               # run that lesson's See It in the Linux lab
```

`just demo` and `just see` work once a lesson ships; until then they say which lesson is missing. `just lab` opens a shell in the lab container (tcpdump, strace, ss, perf, wrk, k6, and all three toolchains) with this repo mounted at `/work`. `just` with no arguments lists every recipe.

---

## Project Structure

```
build-web-apis/
├── apps/
│   ├── python/              # Python 3.12 + uv: src/ticketing/, tests/ (the narrative port)
│   ├── go/                  # Go 1.23: cmd/ticketing/, internal/
│   └── rust/                # Rust stable: src/{main,lib}.rs, tests/
├── demos/                   # demos/<mm>/<ll>/{python,go,rust}, run.sh, see.sh per lesson
├── docs/
│   ├── COURSE-OVERVIEW.md   # audience, prerequisites, reading order, paths
│   ├── LESSON-SKELETON.md   # the binding lesson template
│   ├── SEE-IT-TOOLBOX.md    # the observation tool palette and the lab
│   ├── DIAGRAM-STYLE.md     # Mermaid conventions (flow / stop accents)
│   ├── 00-how-bytes-move/   # one folder per module: 00-OVERVIEW.md, lessons, diagrams/
│   ├── ...
│   ├── 08-run-it/
│   └── superpowers/specs/   # the course design spec
├── db/                      # migrations/NNNN_name.sql (shared by all ports), seed.sql
├── infra/                   # lab/Dockerfile, nginx/, certs/ (gitignored)
├── scripts/                 # lint_lessons.py, migrate.sh, check-tags.sh, certs.sh, capture/, see/
├── .github/workflows/ci.yml # paths-filtered CI on the free tier
├── docker-compose.yml       # postgres, redis, lab (profile)
├── justfile                 # every workflow: up, test, lint, demo, see, ci-local, tag
├── CLAUDE.md                # instructions for coding agents working on this repo
└── CONTRIBUTING.md          # authoring a module, definition of done
```

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Python port | Python 3.12 + uv; FastAPI/Starlette/uvicorn from Module 2 | The narrative port: every mechanism is explained here first |
| Go port | Go 1.23; net/http + chi from Module 2 | Same app, goroutines and the netpoller |
| Rust port | Rust stable; tokio + hyper/axum from Module 2 | Same app, futures and the mio/tokio driver |
| Database | PostgreSQL 16 (`log_statement=all`, `pg_stat_statements`) | Events, seats, orders; locks you can watch |
| Cache / streams | Redis 7 | Sessions, rate limits, job streams |
| Edge | nginx | TLS termination, reverse proxy, caching (Module 5 on) |
| Load | wrk, k6, hey | Honest benchmarks with percentiles |
| Observation | Lab container (Ubuntu 24.04): tcpdump, tshark, strace, ss, perf, py-spy, gdb | Every See It runs here, the same on macOS and CI |
| Task runner | just | One command per workflow, locally and in CI |
| CI | GitHub Actions (ubuntu-latest, paths-filtered, free tier) | Lesson lint, link and diagram checks, three test suites, demo smoke runs |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the module workflow (one worktree and one PR per module), the per-module definition of done and the lesson linter.

## License

[MIT](LICENSE)
