# Module 2: REST Done Properly

> REST is constraints about resources and representations, not JSON over POST. Get semantics right by hand, then let a framework do the plumbing, knowing exactly which plumbing. App gains CRUD on Postgres.

---

## What this module is

This module turns the raw server into a real API, in three parts. First come the semantics, by hand: resources and methods, safe vs idempotent operations, pagination and conditional requests, errors as RFC 9457 problem details, and a hand-written OpenAPI document. Then the plumbing: FastAPI (Starlette, uvicorn, h11), net/http + chi, and axum (hyper, tower), each mapped onto Module 1's raw loop. Finally the data: the Postgres wire protocol by hand, then real drivers (asyncpg, pgx, sqlx) and plain-SQL migrations.

At tag `m2`, `ticketing api` serves CRUD for venues, events, seats and orders on Postgres, and `ticketing rawhttp` still runs. This module also fixes the conventions the parallel modules depend on: one-line registries for subcommands and routes, and pre-assigned migration numbers.

## Why a dedicated module

"REST" usually means JSON over POST with ad-hoc status codes. The real constraints (resources, uniform methods, cacheable representations) are what make retries safe, caches correct and clients simple, and they are cheap to get right before a framework exists. The framework lesson then answers a precise question: which of Module 1's jobs moved into library code, and what did that cost? The Postgres lesson asks the same question about the driver.

## The flow question

When a request flows through a framework into Postgres, **which layers add bytes, copies or round trips, and which only rename the same syscalls?** Method semantics decide whether a request may safely flow twice. ETags let a request stop early with `304` and zero body bytes. Keyset pagination stops the database from walking rows it will throw away. The extended query protocol (Parse, Bind, Execute) is the flow between your pool and Postgres, visible byte for byte in tcpdump.

## Lessons

| # | Lesson | Status |
|---|--------|--------|
| 2.1 | Resources, Methods and Idempotency (`01-RESOURCES-METHODS-AND-IDEMPOTENCY.md`) | Planned |
| 2.2 | Pagination, ETags and Conditional Requests (`02-PAGINATION-ETAGS-AND-CONDITIONAL-REQUESTS.md`) | Planned |
| 2.3 | Errors (RFC 9457) and OpenAPI (`03-ERRORS-RFC-9457-AND-OPENAPI.md`) | Planned |
| 2.4 | Frameworks and What They Do for You (`04-FRAMEWORKS-AND-WHAT-THEY-DO-FOR-YOU.md`) | Planned |
| 2.5 | Postgres and the Wire Protocol (`05-POSTGRES-AND-THE-WIRE-PROTOCOL.md`) | Planned |

Status moves `Planned` → `In progress` → `Done`. Lesson files appear in this folder as `NN-TITLE.md` and follow [`docs/LESSON-SKELETON.md`](../LESSON-SKELETON.md).

### 2.1 Resources, Methods and Idempotency

Resources, method semantics, safe vs idempotent.

- **Demo:** replaying POST and PUT three times
- **App:** `domain/{venue,seat,order}.*`
- **See It:** identical bytes, different outcomes in tcpdump
- **Diagram:** resources and methods
- **Reality checks:** `(idempotent-is-not-safe)`, `(delete-twice-is-200-or-404)`

### 2.2 Pagination, ETags and Conditional Requests

Keyset pagination, entity tags, and conditional GETs.

- **Demo:** keyset pagination + ETags
- **App:** `api/pagination.*`, `api/etag.*`
- **See It:** a `304` with zero body bytes; `EXPLAIN` of OFFSET vs keyset (in 2.5)
- **Diagram:** conditional request flow
- **Reality checks:** `(offset-pagination-is-o-n)`, `(weak-etags-and-compression)`

### 2.3 Errors (RFC 9457) and OpenAPI

Problem-details errors and a hand-written API description.

- **Demo:** a problem+json server, and `openapi/ticketing.yaml` written by hand and linted
- **App:** `api/problem.*`
- **See It:** `curl -i` content-type, `oasdiff` of hand-written vs generated
- **Diagram:** error response anatomy
- **Reality checks:** `(stack-traces-are-not-detail)`, `(openapi-is-not-the-api)`

### 2.4 Frameworks and What They Do for You

FastAPI/Starlette/uvicorn/h11, net/http + chi, axum/hyper/tower, each mapped onto Module 1.

- **Demo:** one `GET /events` per framework beside the raw server, same wrk run
- **App:** `api/` package live (in-memory); framework deps added
- **See It:** `strace` of uvicorn vs raw (same syscalls, more futex), a `py-spy` flamegraph (pydantic's share), pprof `conn.serve`, `RUST_LOG=hyper=trace`, reading `server.go: conn.serve` and hyper's `h1/conn.rs`
- **Diagram:** framework layers over the raw loop
- **Reality checks:** `(frameworks-do-not-change-the-syscalls)`, `(validation-is-your-hot-path)`

### 2.5 Postgres and the Wire Protocol

Parse/Bind/Execute, prepared statements, drivers (asyncpg, pgx, sqlx), migrations.

- **Demo:** a hand-written `pgwire` client
- **App:** `db/migrations/0001_init.sql`, `0002_seed.sql`, `store/*`, `scripts/migrate.sh`; tag `m2`
- **See It:** `tcpdump -A port 5432`, Wireshark pgsql, `log_statement=all`, `EXPLAIN (ANALYZE, BUFFERS)`, `pg_stat_activity`
- **Diagram:** request → pool → Postgres protocol messages
- **Reality checks:** `(orm-is-optional-sql-is-not)`, `(prepared-statements-are-the-protocol)`

## What this module does NOT cover

- **GraphQL, gRPC, streaming**: Module 3.
- **Concurrent write correctness**: Module 4. This module's writes are correct only one at a time.
- **Authentication**: Module 5.
- **ORMs**: deliberately plain SQL. SQLAlchemy, GORM and Diesel are named as alternatives, not used.
- **HATEOAS** beyond a discussion of why few public APIs adopt it.

## Cross-references

- **Previous module:** [`docs/01-http-by-hand/00-OVERVIEW.md`](../01-http-by-hand/00-OVERVIEW.md) built the raw server this module's framework replaces (and keeps running).
- **Next modules:** [`docs/03-other-api-shapes/00-OVERVIEW.md`](../03-other-api-shapes/00-OVERVIEW.md) Modules 3, 4 and 5 branch from tag `m2` in parallel.
- **build-ai-agents server-arch:** [`docs/server-arch/03-FASTAPI-ASYNC-ARCHITECTURE.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/server-arch/03-FASTAPI-ASYNC-ARCHITECTURE.md) FastAPI's async architecture from the application side; lesson 2.4 shows the syscalls under it.
- **Module gate:** M2: frameworks allowed, but the raw server must still run. See [`CLAUDE.md`](../../CLAUDE.md), "Module Gates".
- **Design spec:** [`docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`](../superpowers/specs/2026-10-10-build-web-apis-course-design.md) has the binding conventions and this module's full lesson plan.

## Status

Module overview stub, written in Phase 0. All 5 lessons (2.1–2.5) are planned and none are written yet. The module lands as one PR from branch `module/02-rest-done-properly` and is tagged `m2` when the definition of done in [`CONTRIBUTING.md`](../../CONTRIBUTING.md) passes. The hero diagram (`diagrams/hero.mmd`, rendered to `.excalidraw`, `.svg` and `.png`) is drawn with the module and embedded under the thesis once the first lesson is `Done`.
