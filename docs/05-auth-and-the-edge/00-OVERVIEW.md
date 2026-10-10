# Module 5: Auth and the Edge

> Trust is established at the edge: TLS proves the server, tokens prove the caller, rate limits decide who may flow, and a reverse proxy enforces it first. App gains users, API keys, nginx in front.

---

## What this module is

Everything between the internet and the handler: the TLS 1.3 handshake, observed and then decrypted; identity with password hashing, cookie sessions in Redis and a JWT built by hand; OAuth 2.0 and OIDC with PKCE against a local `dex`; API keys and CORS; rate limiting by hand (token bucket, sliding window, a Redis Lua limiter); and nginx as a reverse proxy in front of the app.

The app gains `api --tls`, users and sessions, OIDC login, API keys, a limiter middleware and an `edge` compose profile with nginx. Migrations `0007`–`0008` belong to this module, and [`scripts/certs.sh`](../../scripts/certs.sh) already creates the local certificates.

## Why a dedicated module

Auth bugs are rarely cryptography bugs. They are flow bugs: a token accepted where it should not be, a limiter keyed on the wrong client, a proxy header trusted from anyone. Building each piece by hand, then watching it in tcpdump and `redis-cli MONITOR`, makes the trust boundary something you can point at.

## The flow question

At the edge the question becomes **who is allowed to flow?** TLS decides whether bytes flow readable or encrypted, and shows what still leaks (SNI). Sessions and tokens decide whether a request reaches a handler at all. A rate limiter is a deliberate stop with a refill rate. CORS decides whether a browser lets a response flow back to a page. A reverse proxy is a second TCP connection that sees every request first and can stop it.

## Lessons

| # | Lesson | Status |
|---|--------|--------|
| 5.1 | TLS Handshake (`01-TLS-HANDSHAKE.md`) | Planned |
| 5.2 | Identity, Sessions and JWT (`02-IDENTITY-SESSIONS-AND-JWT.md`) | Planned |
| 5.3 | OAuth2 and OIDC (`03-OAUTH2-AND-OIDC.md`) | Planned |
| 5.4 | API Keys and CORS (`04-API-KEYS-AND-CORS.md`) | Planned |
| 5.5 | Rate Limiting by Hand (`05-RATE-LIMITING-BY-HAND.md`) | Planned |
| 5.6 | Reverse Proxies and API Gateways (`06-REVERSE-PROXIES-AND-API-GATEWAYS.md`) | Planned |

Status moves `Planned` → `In progress` → `Done`. Lesson files appear in this folder as `NN-TITLE.md` and follow [`docs/LESSON-SKELETON.md`](../LESSON-SKELETON.md).

### 5.1 TLS Handshake

TLS 1.3 step by step: ClientHello, key share, certificates, Finished; what stays visible.

- **Demo:** a TLS echo server (ssl / crypto/tls / rustls)
- **App:** `api --tls`, `scripts/certs.sh`
- **See It:** `openssl s_client -msg -tlsextdebug`, the ClientHello SNI in clear and then ciphertext, Wireshark decryption via `SSLKEYLOGFILE`
- **Diagram:** the TLS 1.3 handshake
- **Reality checks:** `(tls-does-not-hide-sni)`, `(terminate-at-the-edge-encrypt-inside-anyway)`

### 5.2 Identity, Sessions and JWT

Password hashing, cookie sessions, and a JWT (HS256) built with the standard library.

- **Demo:** a JWT by hand (HS256 with stdlib), a cookie session
- **App:** `0007_users.sql`, `auth/{password,session,jwt}.*`, sessions in Redis
- **See It:** cookie attributes, `base64 -d` of the payload, `redis-cli MONITOR`
- **Diagram:** session vs token request paths
- **Reality checks:** `(jwt-is-not-a-session)`, `(localstorage-is-not-httponly)`

### 5.3 OAuth2 and OIDC

The authorization code flow with PKCE, JWKS and RS256, discovery; a local `dex` in compose.

- **Demo:** the full code flow, printing every hop
- **App:** `auth/oidc.*`
- **See It:** each 302, the token-exchange bytes, JWKS `kid` rotation
- **Diagram:** the code-flow sequence
- **Reality checks:** `(implicit-flow-is-dead)`, `(the-id-token-is-not-an-access-token)`

### 5.4 API Keys and CORS

API keys stored like passwords; CORS preflights and what they do and do not protect.

- **Demo:** a server + an HTML page triggering preflights
- **App:** `0008_api_keys.sql`, `auth/apikey.*`, `api/middleware/cors.*`
- **See It:** the OPTIONS preflight in devtools and tcpdump
- **Diagram:** the preflight sequence
- **Reality checks:** `(cors-is-not-security)`, `(api-keys-are-passwords)`

### 5.5 Rate Limiting by Hand

Token and leaky buckets, sliding windows, `429` + `Retry-After`, a Redis Lua limiter (a limiter is a deliberate stop).

- **Demo:** a 30-line bucket; a Redis `EVAL` bucket
- **App:** `api/middleware/ratelimit.*`, `ratelimit/*`
- **See It:** a 429 histogram from `hey -q 0`, `EVALSHA` in MONITOR, refill cadence in `strace -tt`
- **Diagram:** bucket refill and drain
- **Reality checks:** `(rate-limits-need-a-clock-you-trust)`, `(per-ip-is-wrong-behind-nat)`

### 5.6 Reverse Proxies and API Gateways

nginx in front of the app; what a gateway adds; trusting forwarded headers.

- **Demo:** direct vs via nginx, printing the headers the backend saw
- **App:** `infra/nginx/*.conf`, compose `nginx` (profile `edge`), `api/middleware/proxy.*` trusting XFF only from the proxy CIDR; tag `m5`
- **See It:** `nginx -T`, the debug error_log, tcpdump on :443 and :8080 at once (two TCP connections, one request), upstream keepalive in `ss`, `strace -p <worker>`
- **Diagram:** client → nginx → upstream
- **Reality checks:** `(the-proxy-is-a-second-tcp-connection)`, `(gateways-add-a-hop-and-a-vendor)`

## What this module does NOT cover

- **Running a production identity provider**: `dex` stands in for one; the lesson is the protocol, not the product.
- **WebAuthn and passkeys** beyond a pointer.
- **Service-to-service mTLS and service meshes**: named in 5.1, not built.
- **WAF rules and network-scale DDoS mitigation.**

## Cross-references

- **Base module:** [`docs/02-rest-done-properly/00-OVERVIEW.md`](../02-rest-done-properly/00-OVERVIEW.md) provides the API this module puts behind TLS, auth and a proxy (tag `m2`).
- **build-ai-agents infra-arch:** [`docs/infra-arch/10-NGINX-PROXIES-AND-INGRESS.md`](https://github.com/ramanshrivastava/build-ai-agents/blob/main/docs/infra-arch/10-NGINX-PROXIES-AND-INGRESS.md) configures nginx and Ingress; lesson 5.6 builds what that configuration does.
- **Module gate:** M5: nothing listens in plaintext outside compose. See [`CLAUDE.md`](../../CLAUDE.md), "Module Gates".
- **Design spec:** [`docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`](../superpowers/specs/2026-10-10-build-web-apis-course-design.md) has the binding conventions and this module's full lesson plan.

## Status

Module overview stub, written in Phase 0. All 6 lessons (5.1–5.6) are planned and none are written yet. The module lands as one PR from branch `module/05-auth-and-the-edge` and is tagged `m5` when the definition of done in [`CONTRIBUTING.md`](../../CONTRIBUTING.md) passes. The hero diagram (`diagrams/hero.mmd`, rendered to `.excalidraw`, `.svg` and `.png`) is drawn with the module and embedded under the thesis once the first lesson is `Done`.
