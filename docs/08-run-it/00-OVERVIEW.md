# Module 8: Run It

> Shipping is a flow problem too. Kubernetes itself is taught in `build-ai-agents/docs/infra-arch`; here we map this app onto it.

---

## What this module is

Ship the app and keep it running while it changes. The module covers containers for three runtimes (multi-stage builds, namespaces and cgroups, a 40-line container with `unshare`) and the app on Kubernetes with `kind`. It then covers rolling deploys and graceful shutdown, proven with a zero-error rollout test, and API versioning and deprecation, with an `oasdiff` CI gate. It ends with the capstone: one `POST /orders` traced from keypress to confirmation through every layer the course built, with a See It per layer.

The app gains three non-root images, kind manifests (`infra/k8s/`), graceful shutdown in every server, `/healthz` and `/readyz`, versioned routes, and `scripts/trace-everything.sh`, which writes a full capture set to `captures/<timestamp>/`.

## Why a dedicated module

Deploys are where correct code drops requests: a SIGTERM that kills in-flight work, a readiness probe that flips too late, a load balancer that learns about a dead pod after sending it traffic. This module maps the app onto Kubernetes (taught in depth in the build-ai-agents infra-arch series) and concentrates on the flow problems of shipping. The capstone then ties the whole course together.

## The flow question

Shipping is a flow problem too: **how do you change the running system without dropping in-flight requests?** A rolling deploy works only if traffic stops flowing to a pod (readiness false, endpoints updated, the load balancer informed) before the pod stops accepting, and if in-flight requests flow to completion during the drain. A Kubernetes Service is iptables rules deciding where packets flow. Versioning decides which clients may keep flowing to an old contract, and for how long.

## Lessons

| # | Lesson | Status |
|---|--------|--------|
| 8.1 | Containers for Three Runtimes (`01-CONTAINERS-FOR-THREE-RUNTIMES.md`) | Planned |
| 8.2 | Kubernetes for This App (`02-KUBERNETES-FOR-THIS-APP.md`) | Planned |
| 8.3 | Rolling Deploys and Graceful Shutdown (`03-ROLLING-DEPLOYS-AND-GRACEFUL-SHUTDOWN.md`) | Planned |
| 8.4 | API Versioning and Deprecation (`04-API-VERSIONING-AND-DEPRECATION.md`) | Planned |
| 8.5 | The Whole Picture (`05-THE-WHOLE-PICTURE.md`) | Planned |

Status moves `Planned` → `In progress` → `Done`. Lesson files appear in this folder as `NN-TITLE.md` and follow [`docs/LESSON-SKELETON.md`](../LESSON-SKELETON.md).

### 8.1 Containers for Three Runtimes

Multi-stage images (uv → slim, Go → distroless, cargo → distroless), namespaces and cgroups.

- **Demo:** a 40-line "container" via `unshare` + chroot
- **App:** three Dockerfiles
- **See It:** `docker history`, `dive`, `lsns`, `/proc/1/cgroup`, `memory.max`
- **Diagram:** image layers vs the running process
- **Reality checks:** `(alpine-and-musl-dns)`, `(the-image-is-not-the-process)`

### 8.2 Kubernetes for This App

Manifests on `kind`; cross-links to build-ai-agents infra-arch 01, 05, 10 and 11.

- **Demo:** listing Service endpoints via raw HTTPS to the API server
- **App:** `infra/k8s/{base,overlays/kind}`, `scripts/kind-up.sh`
- **See It:** `endpointslices`, `iptables -t nat -L KUBE-SERVICES` / `ipvsadm`, `conntrack` for a VIP, tcpdump inside a pod netns via `nsenter`
- **Diagram:** Service → iptables → pod
- **Reality checks:** `(a-service-is-iptables-not-a-proxy)`, `(hpa-on-cpu-misses-io-bound-apis)`

### 8.3 Rolling Deploys and Graceful Shutdown

SIGTERM, draining, readiness vs liveness, the preStop race, a zero-error rollout as a test.

- **Demo:** `drain`, a server logging its shutdown phases
- **App:** graceful shutdown in `rawhttp` + `api` in all three ports, `/healthz` and `/readyz`, probes
- **See It:** `strace -e rt_sigaction,accept4,close` during SIGTERM, FIN_WAIT in `ss`, `wrk` through `rollout restart` → zero non-2xx, `kubectl get endpoints -w` timing
- **Diagram:** the rollout timeline
- **Reality checks:** `(readiness-false-before-sigterm)`, `(the-lb-learns-late)`

### 8.4 API Versioning and Deprecation

URL vs header vs media-type versions, additive change rules, `Deprecation` / `Sunset` headers, an `oasdiff` CI gate.

- **Demo:** `/v1` + `/v2` from one handler
- **App:** `api/versioning.*`, `openapi/ticketing-v2.yaml`, CI `oasdiff --fail-on breaking`
- **See It:** `curl -i` showing `Deprecation` and `Sunset`, an `oasdiff` breaking-change report
- **Diagram:** one handler, two contracts
- **Reality checks:** `(versioning-the-url-versions-the-whole-api)`, `(deprecation-without-telemetry-is-a-guess)`

### 8.5 The Whole Picture

Capstone: one `POST /orders` from keypress to confirmation through every layer built, with the flow question answered at each.

- **Demo:** `scripts/trace-everything.sh` itself
- **App:** `scripts/trace-everything.sh` producing `captures/<ts>/` (pcap, strace, ss, pg_locks, MONITOR, nginx debug, trace id); tag `m8`
- **See It:** one See It per layer, all from a single run
- **Diagram:** the hero full-stack journey
- **Reality checks:** `(every-layer-has-a-buffer-and-a-limit)`, `(you-will-not-remember-this-without-the-captures)`

## What this module does NOT cover

- **Kubernetes fundamentals**: see the build-ai-agents infra-arch series, starting with doc 01.
- **Cloud-specific managed services** (GKE, EKS, Cloud Run): `kind` is the only cluster.
- **Helm chart authoring and GitOps tooling** (Argo CD, Flux).
- **Multi-cluster federation.**

## Cross-references

- **Previous module:** [`docs/07-distributed-apis/00-OVERVIEW.md`](../07-distributed-apis/00-OVERVIEW.md) is the system this module ships (tag `m7`). Lessons 8.1 and 8.4 may be built alongside Module 7.
- **build-ai-agents infra-arch:** [`docs/infra-arch/01-KUBERNETES-FUNDAMENTALS.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/infra-arch/01-KUBERNETES-FUNDAMENTALS.md) Kubernetes fundamentals; also docs 05, 10 and 11 of that series.
- **Course overview:** [`docs/COURSE-OVERVIEW.md`](../COURSE-OVERVIEW.md) where lesson 8.5's Next link returns.
- **Module gate:** M8: images run as non-root. See [`CLAUDE.md`](../../CLAUDE.md), "Module Gates".
- **Design spec:** [`docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`](../superpowers/specs/2026-10-10-build-web-apis-course-design.md) has the binding conventions and this module's full lesson plan.

## Status

Module overview stub, written in Phase 0. All 5 lessons (8.1–8.5) are planned and none are written yet. The module lands as one PR from branch `module/08-run-it` and is tagged `m8` when the definition of done in [`CONTRIBUTING.md`](../../CONTRIBUTING.md) passes. The hero diagram (`diagrams/hero.mmd`, rendered to `.excalidraw`, `.svg` and `.png`) is drawn with the module and embedded under the thesis once the first lesson is `Done`.
