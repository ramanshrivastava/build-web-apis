# Module 4: Correct Under Load

> Two people must not buy the same seat. Correctness comes from the database's locks, version columns, idempotency keys and an outbox, and you can watch every one of them in `pg_locks`.

---

## What this module is

The double-sell problem, solved and proven. You reproduce transactions and isolation levels by hand in two psql sessions, then compare three fixes for selling one seat twice: `SELECT … FOR UPDATE`, an optimistic `version` column, and a partial unique index, plus seat holds. Next come idempotency keys with request fingerprints, and the outbox pattern with `SKIP LOCKED` workers and Redis Streams. The module ends with a stampede test that hammers one seat and asserts the invariant. That test becomes a CI job.

The app gains `POST /orders`, idempotency middleware, an outbox and `ticketing worker`. Migrations `0004`–`0006` belong to this module.

## Why a dedicated module

Concurrency bugs pass every unit test and appear at the worst possible moment: on-sale day. They are also invisible without the right tools, which is why every lesson here watches `pg_locks` and `pg_stat_activity` while the race happens. Later modules depend on this one: the outbox drives cache invalidation (6.4) and sagas (7.5), and the stampede test is the acceptance test for the distributed on-sale run (7.6).

## The flow question

When thousands of writers converge on one row, **what makes the flow stop safely?** Here the stops are deliberate. A row lock serialises buyers of the hot seat, and a version check rejects a stale write. A unique index refuses a duplicate. An idempotency key turns a retry into a replay. `SKIP LOCKED` lets workers flow around each other instead of queueing. Each lesson shows the stop happening in `pg_locks`, and what flows when it is missing.

## Lessons

| # | Lesson | Status |
|---|--------|--------|
| 4.1 | Transactions and Isolation Levels (`01-TRANSACTIONS-AND-ISOLATION-LEVELS.md`) | Planned |
| 4.2 | The Double-Sell Problem (`02-THE-DOUBLE-SELL-PROBLEM.md`) | Planned |
| 4.3 | Idempotency Keys (`03-IDEMPOTENCY-KEYS.md`) | Planned |
| 4.4 | Outbox and Background Jobs (`04-OUTBOX-AND-BACKGROUND-JOBS.md`) | Planned |
| 4.5 | Proving It: A Stampede Test (`05-PROVING-IT-A-STAMPEDE-TEST.md`) | Planned |

Status moves `Planned` → `In progress` → `Done`. Lesson files appear in this folder as `NN-TITLE.md` and follow [`docs/LESSON-SKELETON.md`](docs/LESSON-SKELETON.md).

### 4.1 Transactions and Isolation Levels

MVCC snapshots, lost updates at Read Committed, serialization failures at Serializable.

- **Demo:** a lost update reproduced at RC, `40001` at Serializable
- **App:** `store/tx.*` with retry
- **See It:** `pg_locks ⋈ pg_stat_activity`, `log_lock_waits`, two psql sessions stepped by hand
- **Diagram:** MVCC snapshots
- **Reality checks:** `(read-committed-is-the-default-and-it-bites)`, `(serializable-is-not-slow-it-is-retry)`

### 4.2 The Double-Sell Problem

`FOR UPDATE` vs an optimistic `version` vs a partial unique index; seat holds.

- **Demo:** 50 buyers for one seat, before and after
- **App:** `db/migrations/0004_seat_locking.sql`, `store/seats.* reserve()`, `POST /orders`
- **See It:** `hey -c 50`, tuple locks in `pg_locks`, `EXPLAIN` with and without the index
- **Diagram:** the race, with and without the lock
- **Reality checks:** `(check-then-act-is-the-bug)`, `(for-update-serializes-the-hot-row)`

### 4.3 Idempotency Keys

Idempotency middleware with request fingerprints; retries after a timeout.

- **Demo:** middleware per framework; a retry after an induced timeout
- **App:** `0005_idempotency.sql`, `api/middleware/idempotency.*`
- **See It:** `tc netem` timeout + retry in tcpdump, the advisory lock in `pg_locks`
- **Diagram:** first request vs replayed request
- **Reality checks:** `(idempotency-keys-need-fingerprints)`, `(idempotency-is-per-client)`

### 4.4 Outbox and Background Jobs

The dual-write problem, the outbox, `SKIP LOCKED`, Redis Streams, workers.

- **Demo:** an outbox worker + a consumer group
- **App:** `0006_outbox.sql`, `outbox/*`, `worker/*`, the `worker` subcommand, compose `redis`
- **See It:** non-blocking `SKIP LOCKED` across two workers, `redis-cli MONITOR` / `XPENDING`, killing a worker mid-job → redelivery
- **Diagram:** outbox → stream → worker
- **Reality checks:** `(exactly-once-is-a-lie)`, `(polling-is-fine)`

### 4.5 Proving It: A Stampede Test

A load harness asserting `COUNT(sold) == DISTINCT seats`; it becomes CI job `stampede`.

- **Demo:** the stampede harness itself
- **App:** `apps/*/tests/stampede_test.*`, `scripts/stampede.sh`; tag `m4`
- **See It:** `pg_stat_activity`, `pg_stat_statements`, p99 before and after
- **Diagram:** the stampede harness against the invariant
- **Reality checks:** `(tests-that-pass-once-prove-nothing)`, `(load-tests-find-correctness-bugs)`

## What this module does NOT cover

- **Distributed transactions and two-phase commit**: lesson 7.5 uses sagas instead.
- **Consensus protocols** (Raft, Paxos): correctness here comes from one Postgres primary.
- **Exactly-once delivery**: lesson 4.4 argues it does not exist end to end, and builds at-least-once + idempotency instead.
- **Kafka and log-based brokers**: Redis Streams are enough to show consumer groups and redelivery.

## Cross-references

- **Base module:** [`docs/02-rest-done-properly/00-OVERVIEW.md`](docs/02-rest-done-properly/00-OVERVIEW.md) provides the store and migrations this module extends (tag `m2`).
- **Distributed APIs:** [`docs/07-distributed-apis/00-OVERVIEW.md`](docs/07-distributed-apis/00-OVERVIEW.md) re-runs this module's stampede invariant across shards and regions in lesson 7.6.
- **Module gate:** M4: every write path has an idempotency test. See [`CLAUDE.md`](CLAUDE.md), "Module Gates".
- **Design spec:** [`docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`](docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md) has the binding conventions and this module's full lesson plan.

## Status

Module overview stub, written in Phase 0. All 5 lessons (4.1–4.5) are planned and none are written yet. The module lands as one PR from branch `module/04-correct-under-load` and is tagged `m4` when the definition of done in [`CONTRIBUTING.md`](CONTRIBUTING.md) passes. The hero diagram (`diagrams/hero.mmd`, rendered to `.excalidraw`, `.svg` and `.png`) is drawn with the module and embedded under the thesis once the first lesson is `Done`.
