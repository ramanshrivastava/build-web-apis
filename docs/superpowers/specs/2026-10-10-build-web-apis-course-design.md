# Build Web APIs: Course Design Spec

**Status:** Approved design (brainstorming output), committed in Phase 0
**Date:** 2026-10-10
**Scope:** the course's goals, locked decisions, binding conventions, module ladder, repo scaffold, definition of done, staffing and verification. Execution order and per-module size budgets live in the orchestrator's working plan, not here.

> A from-first-principles course on web APIs, sibling of `build-ai-agents`: one ticketing service built three times (Python, Go, Rust), from electrons to distributed systems, with every mechanism observed through real tools.

---

## Context

`build-ai-agents` (`/Users/ramanshrivastava/code/work/oss/build-ai-agents`) is a course of long-form markdown lessons wrapped around one real app (the AI Doctor Assistant) that grows module by module. The user wants a sibling course in the empty repo `/Users/ramanshrivastava/code/work/oss/build-web-apis` that teaches web APIs the same way, but starting much lower (electrons → kernel → hand-written HTTP) and finishing at large distributed APIs.

The user's guiding ideas, in their words:
- **"See the internals as much as possible."** Every lesson observes real bytes, syscalls, locks and runtime behaviour with real tools.
- **"A network is a flow of data; what makes it flow?"** This question is the unifying mental model at every layer.
- Readers **begin with Python, then go to Go, then Rust** inside each module.
- **Beautiful architecture diagrams in each lesson.**
- Execute with **Codex and Opus 5.5 teammates**, not in the main (Fable) context.

### What was learned from build-ai-agents and must be copied

- One app is the spine. Each module adds one capability; old paths stay runnable ("two ways to serve the same thing" is a teaching device).
- Lessons: Learning Objectives (understand / mental models / misconceptions), numbered sections why → mechanism → repo code, app-grounding callouts in a plain fence, `> [!WARNING]` + `**Reality check (slug) —**` callouts (regex-exact so the raman-folio site sync can convert them), Key Files table, Summary table, explain-checklist, Next/Previous links.
- "From scratch" means raw protocol first (curl before SDK; the agent loop by hand before frameworks).
- Planning docs with `[S]/[M]/[L]` sizes and `→ verify:` lines are themselves course material.
- README syllabus: `### Module N:` + one-line blockquote thesis + `| Resource | What You'll Learn |` table; `**Live code** —` rows.
- Per-series `00-OVERVIEW.md`: audience, prerequisites ("you do **not** need"), reading order, suggested paths with time estimates, conventions, not-covered, document maintenance.
- Reference files to copy from: `build-ai-agents/README.md`, `docs/agent-arch/00-OVERVIEW.md`, `docs/agent-arch/01-ANTHROPIC-API-FUNDAMENTALS.md` (objectives + callout form), `docs/agent-arch/11-CLAUDE-MANAGED-AGENTS.md` (Reality check + "What People Miss"), `CLAUDE.md` (Wrong/Right table, behaviour rules), `docs/SCOPE-V1.md` (task legend).

### Pitfalls found in build-ai-agents to avoid

- Global lesson numbering broke twice on renames → per-module folders, per-module numbering, pre-assigned migration numbers.
- "Part N of M" headers drifted → one header form, enforced by a linter in CI.
- Lesson links used `./`, which the site sync never rewrote because it looks links up by repo-root path → file-relative links (what GitHub renders), every link linted to resolve from its own file, and the sync taught to resolve links per file (see Conventions).
- No CI, no lesson lint → both exist from Phase 0 (free tier only).
- Module 7 docs left uncommitted → one PR per module; nothing lands outside a PR.

## Locked decisions

| Decision | Choice |
|---|---|
| Languages | Python, Go, Rust as **parallel ports in every module**, always ordered Python → Go → Rust inside a lesson. Python carries the narrative. |
| Spine app | **Ticketing service**: events, venues, seats, orders, payments. |
| Floor | Below packets: electrons → NIC → kernel stack → socket syscalls, then HTTP/1.1 by hand. |
| Code layout | One growing app per language (`apps/python`, `apps/go`, `apps/rust`) with git tags `m1`..`m8`, **plus** `demos/<mm>/<ll>/{python,go,rust}` single-file programs each lesson starts with, plus `scripts/` for captures. |
| Module ladder | 9 modules (0–8), approved. |
| See It | Mandatory `## K. See It:` section per lesson with exact commands, expected-output excerpts and a reproducible `demos/<mm>/<ll>/see.sh` run via `just see mm/ll` in a Linux lab container. |
| Diagrams | ≥1 Mermaid diagram per lesson, plus one rendered hero diagram per module (`docs/NN-slug/diagrams/hero.{excalidraw,svg,png}`, produced with the local `/diagram` skill). |
| Staffing | Opus 5.5 subagents author in isolated worktrees; Codex CLI ports and reviews; Fable orchestrates only. |

## Course-wide conventions (binding for every author)

### Lesson skeleton

```
# <Title>

**Lesson N of M: <Module name>**
**Ticketing Project**

---
## Table of Contents
## Learning Objectives
   After reading this document, you will understand: …
   Key mental models to internalize: …   (first bullet is always the module's flow question)
   Common misconceptions to avoid: …
## 1. <Why>            ## 2. <Mechanism>   (Mermaid diagram lives here)
## 3. Code: Python     ## 4. Code: Go      ## 5. Code: Rust     (always this order)
   each numbered section closes with a plain fence:   TICKETING EXAMPLE: …
## K. See It: <what we observe>
   ### K.1 <tool> — <observation>  (exact command + 3–10 line expected-output excerpt)
   ### Reproduce   → `just see <mm>/<ll>`
## What People Miss
> [!WARNING]
> **Reality check (<slug>) —** …
## Key Files Summary   | File | Role | Language |
## Summary             | Concept | Key Takeaway |
## Checklist: What You Should Be Able to Explain   (- [ ] items)

**Next:** [./LL+1-….md](./…)  **Previous:** [./LL-1-….md](./…)  **Module Overview:** [./00-OVERVIEW.md](./00-OVERVIEW.md)
```

Enforced by `scripts/lint_lessons.py` (CI job `docs`): header regex and N/M agree with folder count; every `> [!WARNING]` followed by `> **Reality check ([\w-]+) —** `; exactly one `## \d+\. See It:` H2; ≥1 ```` ```mermaid ```` block; three code H2s in Python/Go/Rust order; every link resolves relative to the file that contains it (a link that resolves only from the repo root is rejected); Next/Previous/Module Overview present and resolving; Key Files paths exist.

Links are file-relative, which is what GitHub renders: `./02-….md` within a module, `../02-rest-done-properly/00-OVERVIEW.md` across modules, `../../apps/python/…` for code. Root files (README, CLAUDE.md, CONTRIBUTING.md) use `docs/…`, which is already relative. The raman-folio sync (`scripts/sync-teaching-content.mjs`) must resolve each relative link against the lesson's `sourcePath` before looking it up, since today it matches repo-root paths only.

### See It tool palette (authors pick from, lessons name exact invocations)

| Layer | Tools |
|---|---|
| Wire | `tcpdump -i any -nn -X`, `tshark`/Wireshark dissectors (tcp.analysis, http, http2, websocket, quic, pgsql, redis), `SSLKEYLOGFILE` |
| Syscalls | `strace -f -tt -e trace=network,desc,epoll_wait`, `ltrace` |
| Socket state | `ss -tnip`, `ss -lnt`, `/proc/net/tcp`, `/proc/<pid>/fd`, `lsof -p`, `nstat`, `sysctl net.*` |
| Runtime hood | Python: `PYTHONASYNCIODEBUG=1`, `py-spy`, `gdb -p` + `break sock_recv` in `Modules/socketmodule.c`, read `Lib/selectors.py`. Go: `GODEBUG=schedtrace=1000,http2debug=2`, `go tool pprof`, `go tool trace`, read `runtime/netpoll_epoll.go`, `net/http/server.go`. Rust: `RUST_LOG=trace`, `tokio-console`, `cargo flamegraph`, read `mio/.../epoll.rs`, `tokio/src/runtime/io/driver.rs`, `hyper/src/proto/h1/` |
| Data | `EXPLAIN (ANALYZE, BUFFERS)`, `pg_locks ⋈ pg_stat_activity`, `log_statement=all`, `log_lock_waits=on`, `pg_stat_replication`, `redis-cli MONITOR`/`SLOWLOG` |
| Edge | `curl -v --trace-ascii -`, `openssl s_client -msg -tlsextdebug`, nginx `error_log … debug`, `nginx -T` |
| Load/obs | `wrk --latency`, `k6`, `hey`, `/metrics`, Jaeger waterfall, `perf record` + flamegraph |

### Lab container
`tcpdump`/`strace`/`ss`/`/proc` are Linux; the author machine is macOS. Every See It runs in `docker compose run lab` (`infra/lab/Dockerfile`: ubuntu:24.04 + the palette, `cap_add: [NET_ADMIN, NET_RAW, SYS_PTRACE]`, `pid: host`, repo mounted at `/work`). CI's ubuntu runner runs the same `see.sh` with `sudo`.

### App layout: one binary, subcommands (old paths stay runnable)

| | Python | Go | Rust |
|---|---|---|---|
| Entry | `apps/python/src/ticketing/__main__.py` (`uv run ticketing <cmd>`) | `apps/go/cmd/ticketing/main.go` | `apps/rust/src/main.rs` |
| Subcommands by module | m1 `rawhttp`, m2 `api`, m3 `inventory-grpc`, m4 `worker`, m7 `lb` | same | same |
| Package roots | `src/ticketing/{rawhttp,api,domain,store,…}` | `internal/{rawhttp,api,domain,store,…}` | `src/{rawhttp,api,domain,store,…}` |
| Tests | `apps/python/tests/` (pytest) | `*_test.go` | `#[cfg(test)]` + `apps/rust/tests/` |

Shared by all three: `db/migrations/NNNN_name.sql` (plain SQL via `scripts/migrate.sh`), `db/seed.sql`, `proto/inventory.proto`, `openapi/ticketing.yaml`, `infra/nginx/*.conf`. Dispatch and router registration are one-line-per-module registries so parallel modules never conflict.

## Module ladder and lessons

Each lesson line: file — topic · demo · app gain · See It highlights · diagram · reality-check slugs.

### Module 0 — `docs/00-how-bytes-move/` (no app code)
> Before you write an API, watch a byte travel: physics moves it, framing bounds it, addressing directs it, windows pace it, buffers hold it.

1. `01-ELECTRONS-TO-FRAMES.md` — signals, NIC, DMA rings, interrupts/NAPI, Ethernet, MTU · demo: AF_PACKET sniffer printing MACs/EtherType · See: `ip -s link`, `ethtool -S`, `/proc/interrupts`, `/proc/net/softnet_stat`, `tcpdump -e`, shrink MTU and `ping -M do` · diagram: NIC → ring buffer → softirq → sk_buff · `(ring-buffer-drops)`, `(mtu-is-not-1500)`
2. `02-ADDRESSING-AND-ROUTING.md` — IP, ARP, routing, NAT, DNS, UDP · demo: hand-built DNS query over UDP · See: `ip route get`, `ip neigh`, `tcpdump 'arp or udp port 53' -X`, `dig +trace`, `conntrack -L`, `strace -e sendto,recvfrom` · diagram: packet path host → router → NAT · `(dns-is-udp-until-it-isnt)`, `(nat-is-state)`
3. `03-TCP-FLOW-AND-CONGESTION.md` — handshake, seq/ack, rwnd, Nagle/delayed ACK, cwnd/CUBIC/BBR · demo: `slowreader` with tiny `SO_RCVBUF` · See: `ss -tni`, zero-window in tcpdump/Wireshark, `tc netem delay/loss`, `nstat TcpRetransSegs` · diagram: window sliding + congestion phases · `(nagle-and-delayed-ack)`, `(bandwidth-delay-product)`
4. `04-KERNEL-STACK-AND-BUFFERS.md` — sk_buff, send/recv buffers, SYN backlog vs accept queue, SYN cookies, TIME_WAIT, port exhaustion · demo: `neveraccept` (listen, never accept) · See: `ss -lnt` Recv-Q, `nstat ListenOverflows`, `somaxconn`, `/proc/net/tcp` states · diagram: the two queues · `(backlog-is-two-queues)`, `(time-wait-is-not-a-leak)`
5. `05-SOCKET-SYSCALLS.md` — socket/bind/listen/accept/read/write, fds, O_NONBLOCK/EAGAIN, select/poll/epoll/kqueue · demo: blocking echo vs epoll echo (raw epoll in all three) · See: `strace -e network,epoll_*`, `/proc/<pid>/fd`, `lsof`, `ulimit -n` exhaustion · diagram: syscall boundary user ↔ kernel · `(nonblocking-is-not-async)`, `(epoll-is-not-io)`
6. `06-HOW-RUNTIMES-WRAP-SYSCALLS.md` — CPython `socketmodule.c` + GIL release, `selectors.py`, asyncio transports; Go `internal/poll`, netpoller, goroutine park; Rust mio/tokio io driver, hyper · demo: same echo in asyncio / net+goroutines / tokio · See: `strace -f -e epoll_wait,futex` per runtime, `gdb` breakpoint in `sock_recv`, `GODEBUG=schedtrace`, `go tool trace`, `tokio-console`, `RUST_LOG=mio=trace` · diagram: three runtimes over one epoll · `(gil-releases-on-io)`, `(goroutines-are-not-free)`

Adds `scripts/capture/*.sh`, `scripts/see/common.sh`, `infra/lab/Dockerfile`.

### Module 1 — `docs/01-http-by-hand/`
> HTTP/1.1 is text on a TCP stream. Parse it, write it, keep the connection, chunk the body, route the path, then pick a concurrency model and watch where it stalls. App gains `GET /events` with zero libraries.

1. `01-REQUEST-LINE-AND-HEADERS.md` · demo: byte-dump server · app: `rawhttp/parser.*` (`parse_request_head(bytes) -> Request | NeedMore`) · See: `curl --trace-ascii`, `tcpdump -A`, `printf … | nc`, `strace -e read` partial heads · diagram: bytes → parser state machine · `(read-returns-what-it-wants)`, `(headers-are-bytes-not-strings)`
2. `02-BODIES-CONTENT-LENGTH-AND-CHUNKED.md` · demo: `chunky` 1 chunk/s · app: `rawhttp/body.*` · See: `curl --raw`, chunk bytes in tcpdump, Wireshark reassembly, `TCP_NODELAY` via `ss -tni` · diagram: CL vs TE framing · `(smuggling-is-a-framing-bug)`, `(chunked-is-not-streaming-for-free)`
3. `03-KEEP-ALIVE-AND-PIPELINING.md` · demo: 3 requests on one socket · app: `rawhttp/conn.*`, `rawhttp/server.*` accept loop + idle timeout · See: `ss -tnp` across two curls, no new SYN, `strace -e accept4,close` · diagram: connection lifecycle · `(keepalive-timeouts-race)`, `(head-of-line-blocking-is-h1)`
4. `04-A-TINY-ROUTER.md` · demo: 40-line matcher · app: `rawhttp/router.*`, `domain/event.*` in-memory repo, `rawhttp/handlers.*`, tests · See: `curl -i /events/42`, `strace -c`, VmRSS with 10k events · diagram: request → router → handler → bytes · `(405-not-404)`, `(json-is-not-free)`
5. `05-THREE-CONCURRENCY-MODELS.md` — threads, event loop, goroutines/tasks; slow-client backpressure · demo: slowloris client + 3 servers per language · app: `rawhttp --model threads|loop` · See: `wrk --latency`, Send-Q growth, blocked `write()` vs `EAGAIN`, `py-spy dump`, `GODEBUG=schedtrace`, `tokio-console`, `/proc/<pid>/status Threads:` · diagram: three models side by side · `(backpressure-is-a-full-buffer)`, `(event-loops-block-too)`. **Tag `m1`.**

### Module 2 — `docs/02-rest-done-properly/`
> REST is constraints about resources and representations, not JSON over POST. Get semantics right by hand, then let a framework do the plumbing, knowing exactly which plumbing. App gains CRUD on Postgres.

1. `01-RESOURCES-METHODS-AND-IDEMPOTENCY.md` · demo: replay POST/PUT ×3 · app: `domain/{venue,seat,order}.*` · See: identical bytes, different outcomes in tcpdump · `(idempotent-is-not-safe)`, `(delete-twice-is-200-or-404)`
2. `02-PAGINATION-ETAGS-AND-CONDITIONAL-REQUESTS.md` · demo: keyset pagination + ETags · app: `api/pagination.*`, `api/etag.*` · See: 304 with zero body bytes, `EXPLAIN` OFFSET vs keyset (in 2.5) · `(offset-pagination-is-o-n)`, `(weak-etags-and-compression)`
3. `03-ERRORS-RFC-9457-AND-OPENAPI.md` · demo: problem+json server, hand-written `openapi/ticketing.yaml` linted · app: `api/problem.*` · See: `curl -i` content-type, `oasdiff` hand vs generated · `(stack-traces-are-not-detail)`, `(openapi-is-not-the-api)`
4. `04-FRAMEWORKS-AND-WHAT-THEY-DO-FOR-YOU.md` — FastAPI/Starlette/uvicorn/h11; net/http + chi; axum/hyper/tower, each mapped onto Module 1 · demo: one `GET /events` per framework beside the raw server, same wrk run · app: `api/` package live (in-memory), deps added · See: `strace` uvicorn vs raw (same syscalls, more futex), `py-spy` flamegraph (pydantic share), pprof `conn.serve`, `RUST_LOG=hyper=trace`, read `server.go:conn.serve`, `hyper h1/conn.rs` · diagram: framework layers over the raw loop · `(frameworks-do-not-change-the-syscalls)`, `(validation-is-your-hot-path)`
5. `05-POSTGRES-AND-THE-WIRE-PROTOCOL.md` — Parse/Bind/Execute, prepared statements, drivers (asyncpg/pgx/sqlx), migrations · demo: hand-written `pgwire` client · app: `db/migrations/0001_init.sql`, `0002_seed`, `store/*`, `scripts/migrate.sh` · See: `tcpdump -A port 5432`, Wireshark pgsql, `log_statement=all`, `EXPLAIN (ANALYZE, BUFFERS)`, `pg_stat_activity` · diagram: request → pool → pg protocol messages · `(orm-is-optional-sql-is-not)`, `(prepared-statements-are-the-protocol)`. **Tag `m2`.**

### Module 3 — `docs/03-other-api-shapes/`
> REST is one shape. Build the others small enough to see through. App gains nested reads, an inventory service over gRPC, a live seat map, payment callbacks.

1. `01-GRAPHQL-EXECUTOR-BY-HAND.md` · demo: 150-line parser+executor · app: `graphql/*`, `POST /graphql` · See: 1+N queries then `ANY($1)` after dataloader in `log_statement` · `(graphql-is-not-a-database)`, `(n-plus-one-hides-in-resolvers)`
2. `02-PROTOBUF-WIRE-FORMAT.md` · demo: hand varint encode/decode vs codegen · app: `proto/inventory.proto`, generated code committed via `scripts/gen-proto.sh` · See: `xxd` diff, `protoc --decode_raw` · `(proto3-has-no-required)`, `(json-is-not-slower-where-you-think)`
3. `03-HTTP2-FRAMING-AND-GRPC.md` — preface, frames, HPACK, streams, flow-control windows (flow thread), gRPC 5-byte framing, trailers, deadlines · demo: decode captured h2 frames; grpc-hello · app: `inventory/{server,client}.*` (grpcio/grpc-go/tonic), `inventory-grpc` subcommand, api calls it for availability · See: `curl --http2-prior-knowledge`, Wireshark http2 + HPACK table, `grpcurl`, `GODEBUG=http2debug=2`, `GRPC_TRACE=all`, `RUST_LOG=h2=trace`, WINDOW_UPDATE under slow consumer · diagram: one TCP conn, many streams · `(h2-flow-control-is-per-stream-and-per-connection)`, `(grpc-status-lives-in-trailers)`
4. `04-WEBSOCKETS-AND-SSE.md` — upgrade handshake by hand (key+GUID→SHA-1), frames, masking, ping/pong; SSE · demo: raw-socket WebSocket echo; SSE stream · app: `live/{ws,sse,broker}.*`, seat-status stream · See: `101 Switching Protocols` in tcpdump, Wireshark websocket masked payloads, `curl -N`, heartbeat cadence in `strace -e write` · diagram: upgrade + fan-out broker · `(websocket-is-not-pubsub)`, `(proxies-kill-idle-streams)`
5. `05-WEBHOOKS.md` — HMAC+timestamp, replay window, backoff retries, idempotent receivers, dead letters · demo: `fakepay` provider + verifying receiver · app: `webhooks/*`, `POST /webhooks/payments`, `db/migrations/0003_webhooks.sql` · See: signature header bytes, `openssl dgst -hmac` match, backoff timing in `strace -tt -e connect` · `(verify-before-parse)`, `(at-least-once-means-twice)`
6. `06-HTTP3-AND-QUIC.md` · demo: QUIC client (aioquic/quic-go/quinn+h3) printing stream ids + handshake time · app: none required · See: `curl --http3`, `tcpdump udp 443`, Wireshark quic with SSLKEYLOGFILE, RTT vs TCP+TLS · `(h3-is-not-faster-on-lan)`, `(udp-is-blocked-more-than-you-think)`. **Tag `m3`.**

### Module 4 — `docs/04-correct-under-load/`
> Two people must not buy the same seat. Correctness comes from the database's locks, version columns, idempotency keys and an outbox, and you can watch every one of them in `pg_locks`.

1. `01-TRANSACTIONS-AND-ISOLATION-LEVELS.md` · demo: reproduce lost update at RC, `40001` at Serializable · app: `store/tx.*` with retry · See: `pg_locks ⋈ pg_stat_activity`, `log_lock_waits`, two psql sessions stepped by hand · diagram: MVCC snapshots · `(read-committed-is-the-default-and-it-bites)`, `(serializable-is-not-slow-it-is-retry)`
2. `02-THE-DOUBLE-SELL-PROBLEM.md` — `FOR UPDATE` vs optimistic `version` vs partial unique index; seat holds · demo: 50 buyers for one seat before/after · app: `db/migrations/0004_seat_locking.sql`, `store/seats.*reserve()`, `POST /orders` · See: `hey -c 50`, tuple locks in `pg_locks`, `EXPLAIN` with/without index · diagram: the race with and without the lock · `(check-then-act-is-the-bug)`, `(for-update-serializes-the-hot-row)`
3. `03-IDEMPOTENCY-KEYS.md` · demo: middleware per framework; retry after induced timeout · app: `0005_idempotency.sql`, `api/middleware/idempotency.*` · See: `tc netem` timeout + retry in tcpdump, advisory lock in `pg_locks` · `(idempotency-keys-need-fingerprints)`, `(idempotency-is-per-client)`
4. `04-OUTBOX-AND-BACKGROUND-JOBS.md` — dual-write, outbox, `SKIP LOCKED`, Redis Streams, workers · demo: outbox worker + consumer group · app: `0006_outbox.sql`, `outbox/*`, `worker/*`, `worker` subcommand, compose `redis` · See: non-blocking `SKIP LOCKED` across two workers, `redis-cli MONITOR`/`XPENDING`, kill worker mid-job → redelivery · diagram: outbox → stream → worker · `(exactly-once-is-a-lie)`, `(polling-is-fine)`
5. `05-PROVING-IT-A-STAMPEDE-TEST.md` — load harness asserting `COUNT(sold) == DISTINCT seats`, becomes CI job `stampede` · app: `apps/*/tests/stampede_test.*`, `scripts/stampede.sh` · See: `pg_stat_activity`, `pg_stat_statements`, p99 before/after · `(tests-that-pass-once-prove-nothing)`, `(load-tests-find-correctness-bugs)`. **Tag `m4`.**

### Module 5 — `docs/05-auth-and-the-edge/`
> Trust is established at the edge: TLS proves the server, tokens prove the caller, rate limits decide who may flow, and a reverse proxy enforces it first. App gains users, API keys, nginx in front.

1. `01-TLS-HANDSHAKE.md` · demo: TLS echo (ssl / crypto/tls / rustls) · app: `api --tls`, `scripts/certs.sh` · See: `openssl s_client -msg -tlsextdebug`, ClientHello SNI in clear then ciphertext, Wireshark decrypt via SSLKEYLOGFILE · diagram: TLS 1.3 handshake · `(tls-does-not-hide-sni)`, `(terminate-at-the-edge-encrypt-inside-anyway)`
2. `02-IDENTITY-SESSIONS-AND-JWT.md` · demo: JWT by hand (HS256 with stdlib), cookie session · app: `0007_users.sql`, `auth/{password,session,jwt}.*`, sessions in Redis · See: cookie attributes, `base64 -d` the payload, `redis-cli MONITOR` · `(jwt-is-not-a-session)`, `(localstorage-is-not-httponly)`
3. `03-OAUTH2-AND-OIDC.md` — code flow + PKCE, JWKS/RS256, discovery; local `dex` in compose · demo: full code flow printing every hop · app: `auth/oidc.*` · See: each 302, token exchange bytes, JWKS `kid` rotation · diagram: code-flow sequence · `(implicit-flow-is-dead)`, `(the-id-token-is-not-an-access-token)`
4. `04-API-KEYS-AND-CORS.md` · demo: server + HTML page triggering preflights · app: `0008_api_keys.sql`, `auth/apikey.*`, `api/middleware/cors.*` · See: OPTIONS preflight in devtools and tcpdump · `(cors-is-not-security)`, `(api-keys-are-passwords)`
5. `05-RATE-LIMITING-BY-HAND.md` — token/leaky bucket, sliding window, 429 + `Retry-After`, Redis Lua limiter (a limiter is a deliberate stop) · demo: 30-line bucket; Redis `EVAL` bucket · app: `api/middleware/ratelimit.*`, `ratelimit/*` · See: 429 histogram from `hey -q 0`, `EVALSHA` in MONITOR, refill cadence in `strace -tt` · diagram: bucket refill/drain · `(rate-limits-need-a-clock-you-trust)`, `(per-ip-is-wrong-behind-nat)`
6. `06-REVERSE-PROXIES-AND-API-GATEWAYS.md` · demo: direct vs via nginx, print headers backend saw · app: `infra/nginx/*.conf`, compose `nginx` (profile `edge`), `api/middleware/proxy.*` trusts XFF only from proxy CIDR · See: `nginx -T`, debug error_log, tcpdump on :443 and :8080 at once (two TCP conns, one request), upstream keepalive in `ss`, `strace -p <worker>` · diagram: client → nginx → upstream · `(the-proxy-is-a-second-tcp-connection)`, `(gateways-add-a-hop-and-a-vendor)`. **Tag `m5`.**

### Module 6 — `docs/06-fast-and-observable/`
> You cannot make it fast until you can see where time goes. Measure honestly, profile all three runtimes, size the pools, cache what repeats, emit logs/metrics/traces that answer "why was this request slow?"

1. `01-BENCHMARKING-HONESTLY.md` — percentiles, coordinated omission, open vs closed load · demo: tiny open-loop generator per language · app: `scripts/bench/*` + committed results per tag · See: `wrk --latency`, `k6`, `ss -tni` under load, RSS · `(averages-lie)`, `(localhost-benchmarks-lie-differently)`
2. `02-PROFILING-THREE-RUNTIMES.md` · demo: deliberately slow JSON per language, find it · app: `--pprof`/`/debug/pprof`, py-spy recipe, tokio-console flag · See: `py-spy record`, `go tool pprof -http`, `go tool trace`, `perf record -g` + flamegraph, `GODEBUG=gctrace=1` · diagram: sampling profiler model · `(profile-under-load-not-at-rest)`, `(the-gc-is-visible-in-p99)`
3. `03-CONNECTION-POOLS.md` — Little's law, pool exhaustion as backpressure, pgbouncer (a pool is a bounded buffer of connections) · demo: 60-line bounded pool with wait metric · app: tuned `store/pool.*`, HTTP client pools · See: `pg_stat_activity` vs pool max, zero new `connect()` after warmup, `SHOW POOLS` · `(more-connections-is-slower)`, `(pool-per-process-times-processes)`
4. `04-CACHING-AND-COMPRESSION.md` — cache-aside, single-flight, HTTP caching, nginx proxy_cache, gzip/br/zstd · demo: 100 misses → 1 origin call · app: `cache/*`, outbox-driven invalidation, `infra/nginx/cache.conf`, compression middleware · See: MONITOR, `X-Cache-Status`, byte counts compressed vs not · `(cache-invalidation-is-the-outbox-again)`, `(compressing-small-json-is-negative)`
5. `05-STRUCTURED-LOGS-AND-METRICS.md` · demo: hand-rolled histogram + `/metrics` text, then library · app: `observability/{logging,metrics}.*`, compose `prometheus`+`grafana` (profile `observability`), dashboard JSON · See: `promtool`, `histogram_quantile`, logging's `write()` cost in strace · `(labels-are-a-cardinality-bomb)`, `(logs-are-the-most-expensive-signal)`
6. `06-TRACING-AND-SLOS.md` · demo: propagate `traceparent` by hand across two services, then OTel SDK · app: `observability/tracing.*`, compose `jaeger`, `docs/06-…/SLO.md` · See: Jaeger waterfall of `POST /orders` (api → pg → gRPC → redis → outbox), `traceparent` in tcpdump across hops · diagram: trace waterfall · `(tracing-without-propagation-is-logging)`, `(slos-are-promises-not-dashboards)`. **Tag `m6`.**

### Module 7 — `docs/07-distributed-apis/`
> One box is not enough for on-sale day. Spread the flow across boxes and regions without losing the seat invariant.

1. `01-L7-LOAD-BALANCER-BY-HAND.md` · demo: 200-line L7 balancer per language · app: `lb/*`, `lb` subcommand, compose profile `cluster` with 3 api replicas · See: tcpdump both sides (fan-in/out), upstream keepalive pool in `ss`, `splice` in strace (Go `io.Copy`), kill a replica → health-check removal · diagram: LB topology · `(least-conn-beats-round-robin-when-latency-varies)`, `(an-lb-is-a-buffer-too)`
2. `02-SERVICE-DISCOVERY-AND-CONSISTENT-HASHING.md` · demo: hash ring, add/remove node, ~1/N keys move · app: `lb/{discovery,ring}.*`, hash `/events/{id}/*` by id · See: `dig` against compose resolver, TTL re-resolution in tcpdump, key-distribution histogram, `GODEBUG=netdns=go+2` · diagram: ring with virtual nodes · `(dns-ttl-is-a-suggestion)`, `(consistent-hashing-is-not-balanced)`
3. `03-SHARDING-AND-REPLICATION.md` — shard seats by event_id across 2 Postgres; streaming replica; lag; consistency models grounded in what the replica shows · demo: `stale-read` write-then-read-replica · app: `db/shards.yaml`, `store/{shard_router,replica}.*`, compose `postgres-a/b/replica` · See: `pg_stat_replication` LSNs/lag, `log_statement` per shard, `tc netem` on replication link · diagram: shards + replica · `(cross-shard-queries-are-your-new-n-plus-one)`, `(replica-lag-is-a-correctness-bug)`
4. `04-RETRIES-TIMEOUTS-CIRCUIT-BREAKERS-DEADLINES.md` — retry budgets, jitter, breaker states, deadline propagation (`grpc-timeout`, context/tokio/asyncio timeouts), load shedding with 503 (the flow thread's last word) · demo: breaker + budgeted retry vs flaky server · app: `resilience/*`, `api/middleware/deadline.*`, bounded accept queue + shedding · See: retry storm vs budget in tcpdump, jittered backoff in `strace -tt -e connect`, `grpc-timeout` cancelling a pg query, Recv-Q under shedding · diagram: breaker state machine; deadline shrinking per hop · `(retries-amplify-outages)`, `(deadlines-must-shrink-per-hop)`
5. `05-SAGAS.md` — hold → charge → confirm, compensations, orchestration vs choreography, persisted state machine · demo: 3-step saga with failing step 2 · app: `0009_sagas.sql`, `sagas/order_saga.*`, worker runs steps from outbox · See: saga rows via `\watch`, Jaeger across api → worker → fakepay → compensation, `XPENDING` across crash-restart · diagram: saga state machine · `(sagas-are-not-transactions)`, `(compensation-can-fail-too)`
6. `06-ON-SALE-DAY-AND-MULTI-REGION.md` — two "regions" in compose, region-aware routing, global vs local state, failover, the on-sale run with the 4.5 invariant and chaos · app: `infra/compose/cluster.yml`, `scripts/onsale.sh`, `scripts/chaos.sh`, `ONSALE-RESULTS.md` · See: Grafana during run, cross-region lag, LB logs during chaos, duplicate-sales query returns zero rows · diagram: hero multi-region topology · `(multi-region-is-a-consistency-decision-not-a-deploy)`, `(the-first-minute-of-on-sale-is-the-whole-year)`. **Tag `m7`.**

### Module 8 — `docs/08-run-it/`
> Shipping is a flow problem too. Kubernetes itself is taught in `build-ai-agents/docs/infra-arch`; here we map this app onto it.

1. `01-CONTAINERS-FOR-THREE-RUNTIMES.md` — multi-stage images (uv→slim, Go→distroless, cargo→distroless), namespaces/cgroups · demo: 40-line "container" via `unshare`+chroot · app: three Dockerfiles · See: `docker history`, `dive`, `lsns`, `/proc/1/cgroup`, `memory.max` · `(alpine-and-musl-dns)`, `(the-image-is-not-the-process)`
2. `02-KUBERNETES-FOR-THIS-APP.md` — manifests on `kind`; cross-link `build-ai-agents/docs/infra-arch/{01,05,10,11}-*.md` · demo: list Service endpoints via raw HTTPS to the API server · app: `infra/k8s/{base,overlays/kind}`, `scripts/kind-up.sh` · See: `endpointslices`, `iptables -t nat -L KUBE-SERVICES`/`ipvsadm`, `conntrack` for a VIP, tcpdump inside pod netns via `nsenter` · diagram: Service → iptables → pod · `(a-service-is-iptables-not-a-proxy)`, `(hpa-on-cpu-misses-io-bound-apis)`
3. `03-ROLLING-DEPLOYS-AND-GRACEFUL-SHUTDOWN.md` — SIGTERM, drain, readiness vs liveness, preStop race, zero-error rollout as a test · demo: `drain` server logging shutdown phases · app: graceful shutdown in `rawhttp` + `api` all three, `/healthz` `/readyz`, probes · See: `strace -e rt_sigaction,accept4,close` during SIGTERM, FIN_WAIT in `ss`, `wrk` through `rollout restart` → zero non-2xx, `kubectl get endpoints -w` timing · diagram: rollout timeline · `(readiness-false-before-sigterm)`, `(the-lb-learns-late)`
4. `04-API-VERSIONING-AND-DEPRECATION.md` — URL vs header vs media-type, additive rules, `Deprecation`/`Sunset`, `oasdiff` CI gate · demo: `/v1` + `/v2` from one handler · app: `api/versioning.*`, `openapi/ticketing-v2.yaml`, CI `oasdiff --fail-on breaking` · `(versioning-the-url-versions-the-whole-api)`, `(deprecation-without-telemetry-is-a-guess)`
5. `05-THE-WHOLE-PICTURE.md` — capstone: one `POST /orders` from keypress to confirmation through every layer built, one See It per layer, the flow question answered at each · app: `scripts/trace-everything.sh` producing `captures/<ts>/` (pcap, strace, ss, pg_locks, MONITOR, nginx debug, trace id) · diagram: hero full-stack journey · `(every-layer-has-a-buffer-and-a-limit)`, `(you-will-not-remember-this-without-the-captures)`. **Tag `m8`.**

## Phase 0 scaffold (repo tree)

```
build-web-apis/
├── README.md                 # syllabus in sibling format; Quick Start (just up/test/demo/see); tech stack table
├── CLAUDE.md                 # tech stack; "three ports, one app"; Wrong/Right table; module gates; git rules
├── CONTRIBUTING.md           # worktree per module, one PR per module, DoD, linter usage
├── LICENSE (MIT)  .gitignore  justfile  docker-compose.yml   # postgres(16, log_statement/log_lock_waits/pg_stat_statements), redis(7), lab(profile)
├── .github/workflows/ci.yml
├── apps/python/{pyproject.toml,uv.lock,src/ticketing/{__init__,__main__,version}.py,tests/test_smoke.py}
├── apps/go/{go.mod,.golangci.yml,cmd/ticketing/main.go,internal/version/}
├── apps/rust/{Cargo.toml,Cargo.lock,src/{main,lib}.rs,tests/smoke.rs}
├── demos/README.md           # contract: demos/<mm>/<ll>/{python/main.py,go/main.go,rust/main.rs,run.sh,see.sh,README.md}
├── db/{migrations/.gitkeep,seed.sql}
├── infra/{lab/Dockerfile,nginx/,certs/(gitignored)}
├── scripts/{lint_lessons.py,migrate.sh,capture/,see/common.sh,check-tags.sh,certs.sh}
├── docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md   # this design, committed (brainstorming output)
├── docs/{COURSE-OVERVIEW.md,LESSON-SKELETON.md,SEE-IT-TOOLBOX.md}      # at docs root to avoid a second "00-" folder
└── docs/0N-slug/00-OVERVIEW.md  ×9   # stubs: thesis, lesson table marked *Planned*, flow-question paragraph
```

CLAUDE.md module gates: `M0: no app code · M1: stdlib only, no frameworks · M2: frameworks allowed, raw server must still run · M3: no DB tables outside the module's migration · M4: every write path has an idempotency test · M5: nothing listens plaintext outside compose · M6: no lesson without a before/after number · M7: cluster profile passes the 4.5 invariant · M8: images non-root`.

justfile: `up/down`, `lab`, `migrate`, `test` (+ per-lang), `lint` (+ per-lang + `lint-docs`), `demo MOD/LESSON [LANG]`, `see MOD/LESSON`, `demo-smoke`, `check-tags`, `ci-local` (= lint, test, demo-smoke, check-tags), `tag MN`.

CI (`ci.yml`, ubuntu-latest only, `concurrency: cancel-in-progress`, `timeout-minutes` on every job, `dorny/paths-filter` first): `docs` (lint_lessons + lychee offline), `python` (setup-uv cache, ruff, pytest, services postgres+redis), `go` (setup-go cache, golangci-lint, `go test -race`), `rust` (rust-toolchain + rust-cache, clippy -D warnings, cargo test), `demos` (apt tcpdump strace; `just demo-smoke`, only if demos/apps changed), `stampede` (from m4; main pushes only), `tags` (on `m*` tag push: `check-tags.sh`).

## Per-module definition of done

- [ ] `docs/NN-slug/00-OVERVIEW.md`: thesis, what/why, lesson table all `Done`, not-covered, cross-refs, flow-question paragraph; hero diagram rendered in `diagrams/`.
- [ ] README syllabus block complete for the module; no `*Coming soon*` left.
- [ ] Every lesson passes `scripts/lint_lessons.py` (header N of M, Reality-check form, one See It, ≥1 Mermaid, Py→Go→Rs order, file-relative links, resolving Next/Previous, Key Files exist).
- [ ] Every See It names ≥2 tools with exact commands and expected-output excerpts; `demos/NN/LL/see.sh` exits 0 in lab and in CI, printing a line matching its declared `EXPECT=` regex.
- [ ] `demos/NN/LL/{python,go,rust}` run via `just demo`, `--smoke` under 60 s, no external network (0.2 and 3.6 excepted, skipped with `CI_OFFLINE=1`).
- [ ] All three ports pass `just test` and `just lint`; previous subcommands still start and answer `GET /events`.
- [ ] Shared artifacts updated once (`db/migrations` with pre-assigned numbers, `openapi/`, `proto/`, `infra/`).
- [ ] CLAUDE.md gate row present and true.
- [ ] PR merged (conventional commits like `docs(m3): …`, `feat(m3/go): …`; no Claude-Session trailers), Codex review passed, annotated tag `mN`, `check-tags.sh mN` passes, worktree removed and branch deleted.

## Dependencies, parallelism and staffing

```
Phase 0 scaffold ──► M0 ─────────────────┐   (M0 touches no apps/*: parallel with M1)
                 └─► M1 ─► m1 ─► M2 ─► m2
                                   ├─► M3 ┐
                                   ├─► M4 ├─ parallel off m2 (disjoint packages; merge 3→4→5, rebase each)
                                   └─► M5 ┘
                                   M6 ─► m6 ─► M7 ─► m7 ─► M8 ─► m8   (8.1 and 8.4 may run alongside M7)
```

Conflict pre-emption decided in M2: one-line-per-module registries for subcommand dispatch and router registration; pre-assigned migration numbers (M3: 0003; M4: 0004–0006; M5: 0007–0008; M7: 0009); each module appends deps under a `# mN` block and lockfiles are regenerated by the orchestrator at merge; each module adds its own compose profile.

**Staffing per module** (Fable orchestrates; never authors). Roles:

| Role | Runtime | Owns |
|---|---|---|
| Author | Opus (`model: "opus"`, `isolation: "worktree"`, branch `module/NN-slug`) | `00-OVERVIEW.md`, all lessons (prose + Mermaid + Python sections), `diagrams/hero.mmd`, `demos/NN/*/python`, `apps/python`, every `see.sh`/`run.sh`, shared artifacts (`db/migrations`, `openapi`, `proto`, `infra`), `PORT-SPEC.md` (each file's public API + tests) |
| Porter | second Opus agent in the same worktree, started when `PORT-SPEC.md` is committed | `apps/go`, `apps/rust`, `demos/NN/*/{go,rust}`, their tests, and only the `### Go` / `### Rust` subsections of lessons (edited by heading anchor) |
| Reviewer | Codex CLI via `/codex` review mode, `codex exec … < /dev/null`, never interactive | diff review with pass/fail gate against CLAUDE.md gates and the lesson skeleton |
| Challenger | Codex via `/codex` challenge mode inside the lab container | runs every `just see NN/LL` and `just demo NN/LL <lang> --smoke`, re-executes every command printed in a See It section verbatim, diffs expected excerpts vs reality, posts one PR comment table `Lesson | Command | Observed | Fix`; no merge with an open finding |
| Diagram renderer | local `/diagram` skill | `diagrams/hero.mmd` → `hero.{excalidraw,svg,png}` |
| Merger | orchestrator via `/codex-pr-loop` | waits for CI + Codex review, merges in dependency order, tags `mN`, removes worktree, deletes branch |

Sequence inside a module: Author writes overview + lessons (Python sections, Mermaid) + Python demos/app + see.sh + PORT-SPEC.md → Porter ports Go and Rust in parallel while Author polishes → both green on `just test` → `/diagram` renders hero → Codex review → fixes → Codex challenge → fixes → PR → CI → `/codex-pr-loop` merge → tag. Commit scopes `feat(mN/python)`, `feat(mN/go)`, `feat(mN/rust)`, `docs(mN)`; Author rebases last. Heavy modules (3, 5, 7) split the Author into two runs (lessons 1–3, then 4–6). Peak concurrency: three Author/Porter pairs during the M3/M4/M5 band; one `codex exec` at a time. Codex output saved to `.codex/review-mNN.md` (gitignored) and summarised in the PR body.

Diagram conventions (`docs/DIAGRAM-STYLE.md`): `flowchart LR` for pipelines, `sequenceDiagram` for wire exchanges, `stateDiagram-v2` for lifecycles, `classDiagram` only for data models; nodes name real artifacts (`epoll_wait()`, `sk_buff`, `seats.version`), never "Service A"; two class accents, `flow` and `stop`, so the course's question is visible in every figure; first figure sits in the first mechanism section with an italic `*Figure 1 — …*` caption; module overview embeds `hero.svg` under the thesis; CI `docs` job renders every extracted fence with `mmdc` so a broken diagram fails the build. Module 8's hero doubles as the README top image.

Background-process rules from the user's CLAUDE.md apply: verify each launched agent/codex run is producing output within a minute, keep a running list, report in-flight status every reply.

## Verification (end to end)

1. `just ci-local` = lint (ruff, golangci-lint, clippy, `lint_lessons.py`, link check) → test (three ports against compose postgres/redis) → demo-smoke (every `run.sh --smoke` under `timeout 60` in the lab) → check-tags.
2. `scripts/check-tags.sh`: for each `m0..m8`, add a temp worktree, `just test`, assert the expected subcommands start (`rawhttp` from m1, `api` from m2, `inventory-grpc` m3, `worker` m4, `lb` m7) and answer `GET /events` 200 within 10 s, migrations apply cleanly on an empty DB, remove the worktree.
3. `just see NN/LL` for every lesson exits 0 and prints its `EXPECT=` match (e.g. `win 0` for 0.3, `101 Switching Protocols` for 3.4, `ShareLock` for 4.2).
4. Stampede invariant (`scripts/stampede.sh`) against m4 and the m7 cluster profile: duplicate-sales query returns zero rows.
5. Fresh-clone test after each module merge: `git clone && just up && just migrate && just test && just demo 01/04 python && just see 01/04`.
6. Codex challenge pass per module ran every `see.sh` and tried to break the invariant tests; its report is attached to the PR.
