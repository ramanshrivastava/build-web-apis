# Module 3: Other API Shapes

> REST is one shape. Build the others small enough to see through. App gains nested reads, an inventory service over gRPC, a live seat map, payment callbacks.

---

## What this module is

Six shapes beyond request/response JSON, each built small enough to see through: a GraphQL executor by hand (and the N+1 problem it creates), the protobuf wire format by hand, HTTP/2 framing and gRPC, WebSockets and server-sent events, webhooks, and HTTP/3 over QUIC.

The app gains nested reads at `POST /graphql`, a separate inventory service called over gRPC (`ticketing inventory-grpc`), a live seat-status stream, and signed payment callbacks at `POST /webhooks/payments`. Migration `0003` belongs to this module.

## Why a dedicated module

Teams choose GraphQL, gRPC or WebSockets for reasons that are really about flow: who initiates, how many messages share a connection, and who controls the pace. Building each one by hand shows what the protocol actually guarantees, and what it leaves to you (dataloaders, deadlines, heartbeats, idempotent receivers), before a code generator hides it.

## The flow question

Each API shape is a different contract for **who pushes data and when**, so each has its own answer to "what makes it stop". GraphQL resolvers fan out queries unless a dataloader batches them. HTTP/2 multiplexes streams on one connection and paces each with per-stream and per-connection `WINDOW_UPDATE`s. WebSockets push without asking, so a slow consumer needs backpressure or a dropped connection. Webhooks retry with backoff until the receiver returns 2xx. QUIC moves streams into user space, so one lost packet stops only its own stream.

## Lessons

| # | Lesson | Status |
|---|--------|--------|
| 3.1 | GraphQL Executor by Hand (`01-GRAPHQL-EXECUTOR-BY-HAND.md`) | Planned |
| 3.2 | Protobuf Wire Format (`02-PROTOBUF-WIRE-FORMAT.md`) | Planned |
| 3.3 | HTTP/2 Framing and gRPC (`03-HTTP2-FRAMING-AND-GRPC.md`) | Planned |
| 3.4 | WebSockets and SSE (`04-WEBSOCKETS-AND-SSE.md`) | Planned |
| 3.5 | Webhooks (`05-WEBHOOKS.md`) | Planned |
| 3.6 | HTTP/3 and QUIC (`06-HTTP3-AND-QUIC.md`) | Planned |

Status moves `Planned` → `In progress` → `Done`. Lesson files appear in this folder as `NN-TITLE.md` and follow [`docs/LESSON-SKELETON.md`](docs/LESSON-SKELETON.md).

### 3.1 GraphQL Executor by Hand

Parsing and executing GraphQL, resolvers, the N+1 problem and dataloaders.

- **Demo:** a 150-line parser + executor
- **App:** `graphql/*`, `POST /graphql`
- **See It:** 1+N queries, then a single `ANY($1)` after the dataloader, in `log_statement`
- **Diagram:** query → resolvers → SQL fan-out
- **Reality checks:** `(graphql-is-not-a-database)`, `(n-plus-one-hides-in-resolvers)`

### 3.2 Protobuf Wire Format

Varints, field tags and wire types, by hand and generated.

- **Demo:** varint encode/decode by hand vs codegen
- **App:** `proto/inventory.proto`; generated code committed via `scripts/gen-proto.sh`
- **See It:** an `xxd` diff, `protoc --decode_raw`
- **Diagram:** a message's bytes, field by field
- **Reality checks:** `(proto3-has-no-required)`, `(json-is-not-slower-where-you-think)`

### 3.3 HTTP/2 Framing and gRPC

The connection preface, frames, HPACK, streams, flow-control windows, gRPC's 5-byte framing, trailers and deadlines.

- **Demo:** decoding captured h2 frames; grpc-hello
- **App:** `inventory/{server,client}.*` (grpcio / grpc-go / tonic), the `inventory-grpc` subcommand; the API calls it for availability
- **See It:** `curl --http2-prior-knowledge`, Wireshark http2 + the HPACK table, `grpcurl`, `GODEBUG=http2debug=2`, `GRPC_TRACE=all`, `RUST_LOG=h2=trace`, WINDOW_UPDATE under a slow consumer
- **Diagram:** one TCP connection, many streams
- **Reality checks:** `(h2-flow-control-is-per-stream-and-per-connection)`, `(grpc-status-lives-in-trailers)`

### 3.4 WebSockets and SSE

The upgrade handshake by hand (key + GUID → SHA-1), frames, masking, ping/pong; server-sent events.

- **Demo:** a raw-socket WebSocket echo; an SSE stream
- **App:** `live/{ws,sse,broker}.*`, the seat-status stream
- **See It:** `101 Switching Protocols` in tcpdump, masked payloads in Wireshark, `curl -N`, heartbeat cadence in `strace -e write`
- **Diagram:** the upgrade + a fan-out broker
- **Reality checks:** `(websocket-is-not-pubsub)`, `(proxies-kill-idle-streams)`

### 3.5 Webhooks

HMAC + timestamp signatures, replay windows, retries with backoff, idempotent receivers, dead letters.

- **Demo:** `fakepay`, a provider, and a verifying receiver
- **App:** `webhooks/*`, `POST /webhooks/payments`, `db/migrations/0003_webhooks.sql`
- **See It:** signature header bytes, a matching `openssl dgst -hmac`, backoff timing in `strace -tt -e connect`
- **Diagram:** sender → retries → receiver
- **Reality checks:** `(verify-before-parse)`, `(at-least-once-means-twice)`

### 3.6 HTTP/3 and QUIC

QUIC streams over UDP, handshake latency, and when HTTP/3 does not help.

- **Demo:** a QUIC client (aioquic / quic-go / quinn + h3) printing stream ids and handshake time
- **App:** none required; tag `m3`
- **See It:** `curl --http3`, `tcpdump udp 443`, Wireshark quic with `SSLKEYLOGFILE`, RTT vs TCP + TLS
- **Diagram:** QUIC streams vs TCP head-of-line blocking
- **Reality checks:** `(h3-is-not-faster-on-lan)`, `(udp-is-blocked-more-than-you-think)`

## What this module does NOT cover

- **GraphQL federation and subscriptions**, and production GraphQL servers (the executor is a teaching tool).
- **gRPC bidirectional streaming in depth**: availability uses unary calls and one server stream.
- **Message brokers** (Kafka, NATS): Redis Streams arrive in lesson 4.4.
- **SOAP, XML-RPC, WebTransport.**
- **Browser clients** beyond a minimal test page.

## Cross-references

- **Previous module:** [`docs/02-rest-done-properly/00-OVERVIEW.md`](docs/02-rest-done-properly/00-OVERVIEW.md) is the base this module branches from (tag `m2`).
- **Parallel modules:** [`docs/04-correct-under-load/00-OVERVIEW.md`](docs/04-correct-under-load/00-OVERVIEW.md) Modules 4 and 5 are built alongside this one, with disjoint packages; merge order is 3 → 4 → 5.
- **Module gate:** M3: no DB tables outside migration `0003`. See [`CLAUDE.md`](CLAUDE.md), "Module Gates".
- **Design spec:** [`docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`](docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md) has the binding conventions and this module's full lesson plan.

## Status

Module overview stub, written in Phase 0. All 6 lessons (3.1–3.6) are planned and none are written yet. The module lands as one PR from branch `module/03-other-api-shapes` and is tagged `m3` when the definition of done in [`CONTRIBUTING.md`](CONTRIBUTING.md) passes. The hero diagram (`diagrams/hero.mmd`, rendered to `.excalidraw`, `.svg` and `.png`) is drawn with the module and embedded under the thesis once the first lesson is `Done`.
