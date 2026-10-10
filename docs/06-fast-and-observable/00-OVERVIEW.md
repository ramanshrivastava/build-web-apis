# Module 6: Fast and Observable

> You cannot make it fast until you can see where time goes. Measure honestly, profile all three runtimes, size the pools, cache what repeats, emit logs/metrics/traces that answer "why was this request slow?"

---

## What this module is

Measure first, then improve. The module covers benchmarking without lying (percentiles, coordinated omission, open vs closed load), profiling all three runtimes under load, and connection pools sized with Little's law. It continues with caching (cache-aside, single-flight, HTTP caching, nginx `proxy_cache`) and compression. Then structured logs and metrics, with a hand-rolled histogram before the library, and distributed tracing, with `traceparent` propagated by hand before OpenTelemetry, ending in SLOs.

The app gains profiling hooks (`/debug/pprof`, py-spy recipes, a tokio-console flag), tuned pools, a cache with outbox-driven invalidation, `/metrics`, tracing, committed benchmark results per tag, and an `observability` compose profile (Prometheus, Grafana, Jaeger).

## Why a dedicated module

Performance work without measurement is guessing, and most published numbers are measured wrongly. This module makes "no lesson without a before/after number" a gate. It also builds the observability you need to answer "why was this request slow?" in the distributed system of Module 7.

## The flow question

**Where does time go while data flows?** Almost always into a queue: a pool waiting for a free connection, a socket buffer waiting for the reader, a run queue waiting for a CPU, a cache miss waiting on the origin. Little's law turns that into arithmetic: requests in flight = arrival rate × latency. Caches and single-flight are stops that let one request flow to the origin while the others wait for its answer. Traces make every wait visible as a gap in the waterfall.

## Lessons

| # | Lesson | Status |
|---|--------|--------|
| 6.1 | Benchmarking Honestly (`01-BENCHMARKING-HONESTLY.md`) | Planned |
| 6.2 | Profiling Three Runtimes (`02-PROFILING-THREE-RUNTIMES.md`) | Planned |
| 6.3 | Connection Pools (`03-CONNECTION-POOLS.md`) | Planned |
| 6.4 | Caching and Compression (`04-CACHING-AND-COMPRESSION.md`) | Planned |
| 6.5 | Structured Logs and Metrics (`05-STRUCTURED-LOGS-AND-METRICS.md`) | Planned |
| 6.6 | Tracing and SLOs (`06-TRACING-AND-SLOS.md`) | Planned |

Status moves `Planned` → `In progress` → `Done`. Lesson files appear in this folder as `NN-TITLE.md` and follow [`docs/LESSON-SKELETON.md`](docs/LESSON-SKELETON.md).

### 6.1 Benchmarking Honestly

Percentiles, coordinated omission, open vs closed load.

- **Demo:** a tiny open-loop load generator per language
- **App:** `scripts/bench/*` + committed results per tag
- **See It:** `wrk --latency`, `k6`, `ss -tni` under load, RSS
- **Diagram:** open vs closed load models
- **Reality checks:** `(averages-lie)`, `(localhost-benchmarks-lie-differently)`

### 6.2 Profiling Three Runtimes

Sampling profilers, flamegraphs, scheduler and GC traces in Python, Go and Rust.

- **Demo:** deliberately slow JSON per language, then finding it
- **App:** `--pprof` / `/debug/pprof`, a py-spy recipe, a tokio-console flag
- **See It:** `py-spy record`, `go tool pprof -http`, `go tool trace`, `perf record -g` + flamegraph, `GODEBUG=gctrace=1`
- **Diagram:** the sampling profiler model
- **Reality checks:** `(profile-under-load-not-at-rest)`, `(the-gc-is-visible-in-p99)`

### 6.3 Connection Pools

Little's law, pool exhaustion as backpressure, pgbouncer (a pool is a bounded buffer of connections).

- **Demo:** a 60-line bounded pool with a wait metric
- **App:** tuned `store/pool.*`, HTTP client pools
- **See It:** `pg_stat_activity` vs pool max, zero new `connect()` after warm-up, `SHOW POOLS`
- **Diagram:** requests queueing for a bounded pool
- **Reality checks:** `(more-connections-is-slower)`, `(pool-per-process-times-processes)`

### 6.4 Caching and Compression

Cache-aside, single-flight, HTTP caching, nginx `proxy_cache`, gzip/br/zstd.

- **Demo:** 100 misses → 1 origin call
- **App:** `cache/*`, outbox-driven invalidation, `infra/nginx/cache.conf`, compression middleware
- **See It:** `redis-cli MONITOR`, `X-Cache-Status`, byte counts compressed vs not
- **Diagram:** cache-aside with single-flight
- **Reality checks:** `(cache-invalidation-is-the-outbox-again)`, `(compressing-small-json-is-negative)`

### 6.5 Structured Logs and Metrics

Structured logging, counters and histograms, the Prometheus text format, cardinality.

- **Demo:** a hand-rolled histogram + `/metrics` text, then the library
- **App:** `observability/{logging,metrics}.*`, compose `prometheus` + `grafana` (profile `observability`), dashboard JSON
- **See It:** `promtool`, `histogram_quantile`, logging's `write()` cost in strace
- **Diagram:** histogram buckets → quantiles
- **Reality checks:** `(labels-are-a-cardinality-bomb)`, `(logs-are-the-most-expensive-signal)`

### 6.6 Tracing and SLOs

Trace context propagation by hand, then the OpenTelemetry SDK; SLOs and error budgets.

- **Demo:** `traceparent` propagated by hand across two services, then the OTel SDK
- **App:** `observability/tracing.*`, compose `jaeger`, `docs/06-fast-and-observable/SLO.md`; tag `m6`
- **See It:** the Jaeger waterfall of `POST /orders` (api → pg → gRPC → redis → outbox), `traceparent` in tcpdump across hops
- **Diagram:** a trace waterfall
- **Reality checks:** `(tracing-without-propagation-is-logging)`, `(slos-are-promises-not-dashboards)`

## What this module does NOT cover

- **APM vendor products**: the concepts map onto them, but only open-source tools are used.
- **eBPF profilers** in depth (Parca, Pyroscope eBPF mode).
- **CDN configuration**: HTTP caching semantics are covered, edge networks are not.
- **Capacity planning** beyond Little's law and the benchmarks here.
- **Log pipelines at scale** (ELK, Loki clusters).

## Cross-references

- **Previous modules:** [`docs/05-auth-and-the-edge/00-OVERVIEW.md`](docs/05-auth-and-the-edge/00-OVERVIEW.md) Modules 3–5 provide the services, nginx and Redis this module measures (tags `m3`–`m5`).
- **build-ai-agents agent-ops:** [`docs/agent-ops/00-OVERVIEW.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/agent-ops/00-OVERVIEW.md) applies the same observability discipline to agent systems.
- **Module gate:** M6: no lesson without a before/after number. See [`CLAUDE.md`](CLAUDE.md), "Module Gates".
- **Design spec:** [`docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`](docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md) has the binding conventions and this module's full lesson plan.

## Status

Module overview stub, written in Phase 0. All 6 lessons (6.1–6.6) are planned and none are written yet. The module lands as one PR from branch `module/06-fast-and-observable` and is tagged `m6` when the definition of done in [`CONTRIBUTING.md`](CONTRIBUTING.md) passes. The hero diagram (`diagrams/hero.mmd`, rendered to `.excalidraw`, `.svg` and `.png`) is drawn with the module and embedded under the thesis once the first lesson is `Done`.
