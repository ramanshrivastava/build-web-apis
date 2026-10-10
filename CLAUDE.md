# Build Web APIs - Project Instructions

A course repo: long-form lessons in `docs/NN-slug/` wrapped around one ticketing service built three times (`apps/python`, `apps/go`, `apps/rust`), plus one small demo per lesson in `demos/<mm>/<ll>/`. The design spec is `docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`. Read it before authoring a module.

## Tech Stack

- **Python port:** Python 3.12 + uv (not pip). Stdlib only through Module 1; FastAPI/Starlette/uvicorn from lesson 2.4.
- **Go port:** Go 1.23 (`go.mod` minimum). Stdlib through Module 1; net/http + chi from lesson 2.4.
- **Rust port:** Rust stable, edition 2021. std through Module 1; tokio + hyper/axum from lesson 2.4.
- **Data:** PostgreSQL 16 and Redis 7 via `docker-compose.yml` (`just up`). Schema is plain SQL in `db/migrations/`.
- **Edge and load:** nginx (Module 5 on), wrk / k6 / hey.
- **Observation:** the lab container (`infra/lab/Dockerfile`, `just lab`), which has tcpdump, tshark, strace, ss, perf, py-spy, gdb and the three toolchains.
- **Task runner:** `just` for everything. CI calls the same recipes.

## Three Ports, One App

- **Python first, then Go, then Rust.** Python carries the narrative. Go and Rust are faithful ports, not reinterpretations. In every lesson the code sections are `## N. Code: Python`, then `Code: Go`, then `Code: Rust`.
- **Same names everywhere.** Packages, files, functions, types, routes, JSON fields, error codes and log keys match across ports, adjusted only for language casing: `rawhttp/parser.py: parse_request_head` = `internal/rawhttp/parser.go: ParseRequestHead` = `src/rawhttp/parser.rs: parse_request_head`.
- **Same binary shape.** One binary named `ticketing`, with subcommands: `version` (m0), `rawhttp` (m1), `api` (m2), `inventory-grpc` (m3), `worker` (m4), `lb` (m7). Same flags and same output lines. `ticketing version` prints `ticketing X.Y.Z (<lang>)`.
- **Old paths stay runnable.** A new module never removes or breaks an earlier subcommand. `scripts/check-tags.sh` starts every one of them at every tag.
- **One-line registries.** Each module adds exactly one line to the subcommand registry (`COMMANDS` in `__main__.py`, `commands` in `main.go`, `COMMANDS` + one `dispatch` arm in `main.rs`) and one line to router registration. Never reorder other modules' lines.
- **CLI contract.** Network subcommands take `--addr HOST:PORT` (defaults: `api` 127.0.0.1:8080, `rawhttp` 127.0.0.1:8081, `lb` 127.0.0.1:8000, `inventory-grpc` 127.0.0.1:50051). `lb` also takes `--upstream URL` (repeatable). Configuration comes from env: `DATABASE_URL`, `REDIS_URL`.
- **Tests are twins.** A test in one port has a same-named twin in the other two.

| | Python | Go | Rust |
|---|---|---|---|
| Entry | `apps/python/src/ticketing/__main__.py` (`uv run ticketing <cmd>`) | `apps/go/cmd/ticketing/main.go` | `apps/rust/src/main.rs` |
| Package roots | `src/ticketing/{rawhttp,api,domain,store,…}` | `internal/{rawhttp,api,domain,store,…}` | `src/{rawhttp,api,domain,store,…}` |
| Tests | `apps/python/tests/` (pytest) | `*_test.go` beside the code | `#[cfg(test)]` + `apps/rust/tests/` |

Shared by all three ports, and changed once per module: `db/migrations/NNNN_name.sql`, `db/seed.sql`, `proto/inventory.proto`, `openapi/ticketing.yaml`, `infra/nginx/*.conf`.

## Common Mistakes to Avoid

| Wrong | Right |
|-------|-------|
| Global lesson numbers (`docs/23-…`) | Per-module folders and numbering: `docs/NN-slug/LL-TITLE.md` |
| `**Part 3 of 9**`, or any other header form | Line 3 `**Lesson N of M: <Module name>**`, line 4 `**Ticketing Project**` |
| Links like `./02-X.md` or `../01-…/X.md` | Repo-root-relative links: `docs/01-http-by-hand/02-BODIES-CONTENT-LENGTH-AND-CHUNKED.md` |
| `**Reality Check:**` or `> **Reality check —**` without a slug | `> [!WARNING]` then `> **Reality check (kebab-slug) —** …` |
| Go or Rust code before Python | `Code: Python` → `Code: Go` → `Code: Rust`, always |
| Describing output you did not capture | Run the command, paste a 3–10 line excerpt, and make `see.sh` assert it via `EXPECT=` |
| Running tcpdump/strace/ss on macOS | Run them in the lab: `just lab` or `just see MM/LL` |
| A framework or HTTP library in Module 1 | Module 1 is stdlib only; frameworks arrive in lesson 2.4 |
| Replacing the raw server once the framework exists | Keep `rawhttp` running beside `api`; old subcommands never break |
| Taking the next free migration number | Use the pre-assigned numbers: M2 0001–0002, M3 0003, M4 0004–0006, M5 0007–0008, M7 0009 |
| ORM-generated or auto-migrated schema | Plain SQL in `db/migrations/`, applied by `scripts/migrate.sh` |
| Diagram nodes named "Service A", "Server", "DB" | Real artifacts: `epoll_wait()`, `sk_buff`, `seats.version`, `pg_locks` |
| A test that calls the internet or an LLM | Tests use only compose postgres/redis and in-process servers on `127.0.0.1:0` |
| "Go/Rust port to follow" | All three ports land in the same module PR |
| An average latency, or a number without its command | p50/p99 with the exact `wrk`/`k6`/`hey` command and the before/after values |
| Use pip | Use uv |
| Committing to `main`, or work outside a PR | Worktree per module, branch `module/NN-slug`, one PR per module |
| `Claude-Session:` trailers or claude.ai links in commits/PRs | Plain conventional commits |
| `codex exec "…"` left waiting on stdin | `codex exec … < /dev/null`, or the prompt on stdin: `codex exec … - < prompt.md` |

## Module Gates

A module PR merges only when its gate holds. Each row is checked in review and, where noted, by tooling.

| Module | Gate | Checked by |
|--------|------|------------|
| M0 | No app code: `apps/` untouched. Demos, scripts and the lab only | Review: diff has no `apps/` paths |
| M1 | Stdlib only, no frameworks or HTTP libraries in any port | Review: no new deps in `pyproject.toml`, `go.mod`, `Cargo.toml` |
| M2 | Frameworks allowed; the raw server must still run | `check-tags.sh m2` starts `rawhttp` and `api` |
| M3 | No DB tables outside the module's migration (`0003`) | Review of `db/migrations/` |
| M4 | Every write path has an idempotency test | Review + `stampede` CI job |
| M5 | Nothing listens in plaintext outside compose | Review + `check-tags.sh m5` |
| M6 | No lesson without a before/after number | Review of each lesson's See It |
| M7 | The `cluster` profile passes the 4.5 invariant (zero double sales) | `scripts/stampede.sh` against the cluster profile |
| M8 | Images run as non-root | Review + `docker inspect` user in lesson 8.1 |

## Testing Conventions

- **Python:** pytest, `just test-python` (`uv run pytest` in `apps/python`).
- **Go:** `go test -race ./...`, `just test-go`.
- **Rust:** `cargo test` (unit tests in `#[cfg(test)]`, integration tests in `apps/rust/tests/`), `just test-rust`.
- **LLM-free and internet-free.** Tests reach only the compose services (`DATABASE_URL`, `REDIS_URL`) and servers they start themselves on `127.0.0.1:0`.
- **Compose services.** From Module 2, `just up && just migrate` before `just test`. CI provides the same postgres:16 and redis:7 as job services.
- Run `just test` before every commit and `just lint` before opening a PR. `just ci-local` runs everything CI runs.

## Code Style

- **Python:** ruff (check + format, config in `apps/python/pyproject.toml`), type hints on every function.
- **Go:** gofmt + golangci-lint (`apps/go/.golangci.yml`).
- **Rust:** rustfmt + clippy with `-D warnings`.
- Teaching code: names that say what the bytes are, small functions, early returns, comments that explain *why* the mechanism works, and no cleverness the lesson does not teach.

## Git Workflow

- `main` only moves through PRs. Nothing lands outside a PR.
- One module = one worktree = one branch `module/NN-slug` (for example `module/03-other-api-shapes`) = one PR. Create worktrees under `.claude/worktrees/` (gitignored) or with the Agent tool's `isolation: "worktree"`.
- Conventional commits with module scopes: `docs(m3): …`, `feat(m3/python): …`, `feat(m3/go): …`, `feat(m3/rust): …`, `fix(m3/go): …`, `test(m4/rust): …`, `ci: …`, `chore: …`.
- No `Claude-Session:` trailers and no claude.ai links in commits or PR bodies.
- After merge: `just tag mN` on a clean `main` (annotated tag, verified by `check-tags.sh`), then push the tag, then `git worktree remove <path> && git branch -D module/NN-slug && git worktree prune`.
- CI stays on the free tier. If Actions minutes run out, run `just ci-local` and say so in the PR body.

## Codex Rules

- **Never interactive.** Run `codex exec … < /dev/null` or feed the prompt on stdin (`codex exec … - < prompt.md`). An unredirected `codex exec` hangs on "Reading additional input from stdin".
- One `codex exec` at a time. Within a minute of launch, check that it is producing output.
- Save output to `.codex/review-mNN.md` or `.codex/challenge-mNN.md` (gitignored) and summarise it in the PR body.
- **Reviewer:** reviews the diff only, and passes or fails it against the module gate above and `docs/LESSON-SKELETON.md`.
- **Challenger:** runs every `just see NN/LL` and `just demo NN/LL <lang> --smoke` in the lab, re-executes each command printed in a See It section verbatim, and posts one PR comment table `Lesson | Command | Observed | Fix`. The Challenger may not push, tag, merge or edit `apps/`. No merge while a finding is open.

## Key Documentation

- `docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md`: the design, module ladder and every lesson's demo, app gain, See It and reality checks
- `docs/LESSON-SKELETON.md`: the binding lesson template (enforced by `scripts/lint_lessons.py`)
- `docs/SEE-IT-TOOLBOX.md`: the observation palette and how the lab works
- `docs/DIAGRAM-STYLE.md`: Mermaid conventions and the `flow` / `stop` accents
- `demos/README.md`: the demo layout contract (`run.sh`, `see.sh`, `EXPECT=`)
- `CONTRIBUTING.md`: authoring workflow, definition of done, Author/Porter ownership

## Repo Structure

```
build-web-apis/
├── apps/{python,go,rust}/     # the ticketing service, three ports
├── demos/<mm>/<ll>/           # per-lesson demos: python/ go/ rust/ run.sh see.sh
├── docs/NN-slug/              # module folders: 00-OVERVIEW.md, LL-*.md, diagrams/
├── db/                        # migrations/ (pre-assigned numbers), seed.sql
├── infra/                     # lab/Dockerfile, nginx/, certs/
├── scripts/                   # lint_lessons.py, migrate.sh, check-tags.sh, certs.sh, capture/, see/
├── docker-compose.yml         # postgres, redis, lab (+ profiles added per module)
├── justfile                   # every workflow
└── .github/workflows/ci.yml   # paths-filtered, ubuntu-latest, free tier
```

---

## Behavioral Guidelines

Guidelines to reduce common LLM coding mistakes. Merge them with the project rules above.

**Tradeoff:** these guidelines favour caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

- State your assumptions explicitly. If you are uncertain, ask.
- If multiple interpretations exist, present them; do not pick one silently.
- If a simpler approach exists, say so, and push back when warranted.
- If a See It output differs from what the lesson claims, stop: the lesson is wrong until the capture agrees.

### 2. Simplicity First

**Minimum code that teaches the mechanism. Nothing speculative.**

- No features beyond the lesson. No abstractions for single-use code.
- Demos are single files that a reader can hold in their head. If a demo needs a framework, it belongs in `apps/`.
- If you write 200 lines and it could be 50, rewrite it.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

- Stay inside your module: your lesson files, your packages, your registry line, your migration numbers.
- Don't "improve" another module's code, prose or formatting. Mention problems instead of fixing them in passing.
- Remove imports and helpers that *your* change made unused, and nothing else.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

State a brief plan for multi-step work:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

For example: "Port the chunked decoder to Go → verify: `go test -race ./internal/rawhttp/` passes the same cases as `tests/test_body.py`." Strong criteria (`just test`, `just see 01/02`, `scripts/lint_lessons.py`) let you loop on your own; weak ones ("make it work") need constant clarification.

---

**These guidelines are working if:** diffs contain fewer unnecessary changes, fewer rewrites are needed because of overcomplication, and clarifying questions come before implementation rather than after mistakes.
