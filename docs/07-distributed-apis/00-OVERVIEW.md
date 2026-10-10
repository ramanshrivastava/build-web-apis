# Module 7: Distributed APIs

> One box is not enough for on-sale day. Spread the flow across boxes and regions without losing the seat invariant.

---

## What this module is

From one box to many: an L7 load balancer by hand; service discovery and consistent hashing; sharding seats by event across two Postgres instances, with a streaming replica; retries, timeouts, circuit breakers, deadline propagation and load shedding; sagas for hold → charge → confirm, with compensations; and a two-region on-sale day under chaos, where the stampede invariant from lesson 4.5 must still hold.

The app gains `ticketing lb`, a shard router, replica reads, resilience middleware, an order saga and a `cluster` compose profile with three API replicas. Migration `0009` belongs to this module.

## Why a dedicated module

Distribution multiplies every failure mode from earlier modules. Replica lag is a stale read. A retry storm is a self-inflicted DDoS. A missing deadline is a query that keeps running after nobody is waiting for it. Building the balancer and the resilience pieces by hand, then running on-sale day under chaos, shows which guarantees survive the network and which were only ever local.

## The flow question

When flow spreads across boxes, **what keeps it balanced, and what stops it from amplifying failure?** Load balancers and hash rings decide where each request flows. Replication decides where writes flow, and how late they arrive. Retries and backoff decide whether a failure flows outward or dies where it started. Circuit breakers, deadlines and `503` shedding are the course's last deliberate stops: they refuse work early so the rest of the system keeps working.

## Lessons

| # | Lesson | Status |
|---|--------|--------|
| 7.1 | L7 Load Balancer by Hand (`01-L7-LOAD-BALANCER-BY-HAND.md`) | Planned |
| 7.2 | Service Discovery and Consistent Hashing (`02-SERVICE-DISCOVERY-AND-CONSISTENT-HASHING.md`) | Planned |
| 7.3 | Sharding and Replication (`03-SHARDING-AND-REPLICATION.md`) | Planned |
| 7.4 | Retries, Timeouts, Circuit Breakers, Deadlines (`04-RETRIES-TIMEOUTS-CIRCUIT-BREAKERS-DEADLINES.md`) | Planned |
| 7.5 | Sagas (`05-SAGAS.md`) | Planned |
| 7.6 | On-Sale Day and Multi-Region (`06-ON-SALE-DAY-AND-MULTI-REGION.md`) | Planned |

Status moves `Planned` → `In progress` → `Done`. Lesson files appear in this folder as `NN-TITLE.md` and follow [`docs/LESSON-SKELETON.md`](docs/LESSON-SKELETON.md).

### 7.1 L7 Load Balancer by Hand

Balancing algorithms, health checks, upstream keep-alive pools.

- **Demo:** a 200-line L7 balancer per language
- **App:** `lb/*`, the `lb` subcommand, compose profile `cluster` with 3 API replicas
- **See It:** tcpdump on both sides (fan-in/fan-out), the upstream keepalive pool in `ss`, `splice` in strace (Go's `io.Copy`), killing a replica → health-check removal
- **Diagram:** the LB topology
- **Reality checks:** `(least-conn-beats-round-robin-when-latency-varies)`, `(an-lb-is-a-buffer-too)`

### 7.2 Service Discovery and Consistent Hashing

DNS-based discovery, TTLs, hash rings with virtual nodes.

- **Demo:** a hash ring; add or remove a node and ~1/N keys move
- **App:** `lb/{discovery,ring}.*`, hashing `/events/{id}/*` by id
- **See It:** `dig` against the compose resolver, TTL re-resolution in tcpdump, a key-distribution histogram, `GODEBUG=netdns=go+2`
- **Diagram:** a ring with virtual nodes
- **Reality checks:** `(dns-ttl-is-a-suggestion)`, `(consistent-hashing-is-not-balanced)`

### 7.3 Sharding and Replication

Sharding seats by `event_id` across two Postgres instances; a streaming replica; lag; consistency models grounded in what the replica shows.

- **Demo:** `stale-read`: write, then read the replica
- **App:** `db/shards.yaml`, `store/{shard_router,replica}.*`, compose `postgres-a/b/replica`
- **See It:** `pg_stat_replication` LSNs and lag, `log_statement` per shard, `tc netem` on the replication link
- **Diagram:** shards + replica
- **Reality checks:** `(cross-shard-queries-are-your-new-n-plus-one)`, `(replica-lag-is-a-correctness-bug)`

### 7.4 Retries, Timeouts, Circuit Breakers, Deadlines

Retry budgets, jitter, breaker states, deadline propagation (`grpc-timeout`, context / tokio / asyncio timeouts), load shedding with 503.

- **Demo:** a breaker + a budgeted retry against a flaky server
- **App:** `resilience/*`, `api/middleware/deadline.*`, a bounded accept queue + shedding
- **See It:** a retry storm vs a budget in tcpdump, jittered backoff in `strace -tt -e connect`, `grpc-timeout` cancelling a pg query, Recv-Q under shedding
- **Diagram:** the breaker state machine; a deadline shrinking per hop
- **Reality checks:** `(retries-amplify-outages)`, `(deadlines-must-shrink-per-hop)`

### 7.5 Sagas

Hold → charge → confirm, compensations, orchestration vs choreography, a persisted state machine.

- **Demo:** a 3-step saga with a failing step 2
- **App:** `0009_sagas.sql`, `sagas/order_saga.*`, the worker runs steps from the outbox
- **See It:** saga rows via `\watch`, Jaeger across api → worker → fakepay → compensation, `XPENDING` across a crash and restart
- **Diagram:** the saga state machine
- **Reality checks:** `(sagas-are-not-transactions)`, `(compensation-can-fail-too)`

### 7.6 On-Sale Day and Multi-Region

Two "regions" in compose, region-aware routing, global vs local state, failover, and the on-sale run with the 4.5 invariant and chaos.

- **Demo:** the on-sale run itself
- **App:** `infra/compose/cluster.yml`, `scripts/onsale.sh`, `scripts/chaos.sh`, `ONSALE-RESULTS.md`; tag `m7`
- **See It:** Grafana during the run, cross-region lag, LB logs during chaos, the duplicate-sales query returning zero rows
- **Diagram:** the hero multi-region topology
- **Reality checks:** `(multi-region-is-a-consistency-decision-not-a-deploy)`, `(the-first-minute-of-on-sale-is-the-whole-year)`

## What this module does NOT cover

- **Consensus protocols and building a database**: Postgres stays the source of truth for every shard.
- **Service meshes**: this module builds the balancing and resilience a mesh would provide.
- **Global anycast, BGP and real multi-region networking**: the two regions are compose networks with injected latency.
- **CRDTs and leaderless replication**: named in 7.6 as the alternative to a single-writer seat.

## Cross-references

- **Previous module:** [`docs/06-fast-and-observable/00-OVERVIEW.md`](docs/06-fast-and-observable/00-OVERVIEW.md) provides the benchmarks, pools and traces this module relies on to see a distributed request (tag `m6`).
- **Correct Under Load:** [`docs/04-correct-under-load/00-OVERVIEW.md`](docs/04-correct-under-load/00-OVERVIEW.md) defines the stampede invariant that lesson 7.6 must keep across regions.
- **Module gate:** M7: the `cluster` profile passes the 4.5 invariant. See [`CLAUDE.md`](CLAUDE.md), "Module Gates".
- **Design spec:** [`docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`](docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md) has the binding conventions and this module's full lesson plan.

## Status

Module overview stub, written in Phase 0. All 6 lessons (7.1–7.6) are planned and none are written yet. The module lands as one PR from branch `module/07-distributed-apis` and is tagged `m7` when the definition of done in [`CONTRIBUTING.md`](CONTRIBUTING.md) passes. The hero diagram (`diagrams/hero.mmd`, rendered to `.excalidraw`, `.svg` and `.png`) is drawn with the module and embedded under the thesis once the first lesson is `Done`.
