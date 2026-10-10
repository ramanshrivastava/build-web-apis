# Contributing

Thanks for your interest in contributing to Build Web APIs! The course grows one module at a time. Each module is one worktree, one branch and one PR, and it carries its lessons, demos and all three ports of the app.

## Dev Environment Setup

You need Docker (Compose v2), [just](https://just.systems), Python 3.12+ with [uv](https://docs.astral.sh/uv/), Go 1.23+, and Rust stable via rustup (with `clippy` and `rustfmt`). `psql` and `golangci-lint` on the host are optional: without `psql`, run `just lab` and use the lab's copy; without `golangci-lint`, `just lint-go` falls back to `go vet`.

```bash
just up          # postgres 16 + redis 7
just migrate     # apply db/migrations
just test        # all three ports
just lint        # ruff, golangci-lint, clippy, lesson linter, link check
```

### Recipes

| Recipe | What it does |
|--------|--------------|
| `just up` / `just down` | Start (and wait for healthy) / stop postgres and redis |
| `just lab [CMD]` | Shell in the Linux lab container, or run `CMD` there; the repo is at `/work` |
| `just migrate [--seed]` | Apply `db/migrations/*.sql` once each; `--seed` also loads `db/seed.sql` |
| `just test` | `test-python`, `test-go` (`-race`), `test-rust` |
| `just lint` | `lint-python`, `lint-go`, `lint-rust`, `lint-docs` |
| `just lint-docs` | `scripts/lint_lessons.py` + offline link check (lychee, or its Docker image) |
| `just demo MM/LL [LANG] [--smoke]` | Run a lesson's demo; `LANG` is `python`, `go`, `rust` or `all` (default) |
| `just see MM/LL` | Run a lesson's `see.sh`: in the lab on macOS, directly on Linux |
| `just demo-smoke` | Every `demos/*/*/run.sh LANG --smoke` with a 60 s cap |
| `just check-tags [mN…]` | Verify tags in temporary worktrees (tests pass, subcommands start) |
| `just ci-local` | lint + test + demo-smoke + check-tags: what CI checks, run locally |
| `just tag mN` | Annotated tag on a clean `main`, verified by `check-tags.sh`; never pushes |

## Authoring a Module

Read `docs/superpowers/specs/2026-10-10-build-web-apis-course-design.md` (the module's lessons, demos, See It tools and reality-check slugs are listed there), `docs/LESSON-SKELETON.md`, `docs/SEE-IT-TOOLBOX.md` and `docs/DIAGRAM-STYLE.md`.

1. **Create the worktree** from an up-to-date `main`:
   ```bash
   git worktree add .claude/worktrees/03-other-api-shapes -b module/03-other-api-shapes main
   cd .claude/worktrees/03-other-api-shapes
   ```
2. **Write the overview first.** Fill in `docs/NN-slug/00-OVERVIEW.md` and keep its lesson table current (`Planned` → `In progress` → `Done`).
3. **For each lesson:** copy the skeleton from `docs/LESSON-SKELETON.md`, build `demos/NN/LL/` (see `demos/README.md`), write the Python sections, run the See It commands in the lab, and paste real output excerpts. Commit `PORT-SPEC.md` (each new file's public API and tests) so the Porter can start.
4. **Port** to Go, then Rust: the same names, subcommands and tests.
5. **Render the hero diagram** from `diagrams/hero.mmd` into `hero.{excalidraw,svg,png}` with the `/diagram` skill.
6. **Verify** with `just test`, `just lint`, `just demo-smoke` and `just see NN/LL` for every lesson.
7. **Review:** Codex review, then Codex challenge (see CLAUDE.md, "Codex Rules"). Fix every finding.
8. **Open one PR** for the module. After merge: `just tag mN`, push the tag, remove the worktree and delete the branch.

Shared artifacts change once per module, at pre-assigned numbers: migrations (M2 0001–0002, M3 0003, M4 0004–0006, M5 0007–0008, M7 0009), `openapi/`, `proto/` and `infra/`. Each module appends its dependencies under a `# mN` comment. The orchestrator regenerates lockfiles at merge time.

## Per-Module Definition of Done

- [ ] `docs/NN-slug/00-OVERVIEW.md`: thesis, what/why, lesson table all `Done`, not-covered, cross-refs, flow-question paragraph; hero diagram rendered in `diagrams/`.
- [ ] README syllabus block complete for the module; no `*Coming soon*` left.
- [ ] Every lesson passes `scripts/lint_lessons.py` (header N of M, Reality-check form, one See It, ≥1 Mermaid, Py→Go→Rs order, root links, resolving Next/Previous, Key Files exist).
- [ ] Every See It names ≥2 tools with exact commands and expected-output excerpts; `demos/NN/LL/see.sh` exits 0 in lab and in CI, printing a line matching its declared `EXPECT=` regex.
- [ ] `demos/NN/LL/{python,go,rust}` run via `just demo`, `--smoke` under 60 s, no external network (0.2 and 3.6 excepted, skipped with `CI_OFFLINE=1`).
- [ ] All three ports pass `just test` and `just lint`; previous subcommands still start and answer `GET /events`.
- [ ] Shared artifacts updated once (`db/migrations` with pre-assigned numbers, `openapi/`, `proto/`, `infra/`).
- [ ] CLAUDE.md gate row present and true.
- [ ] PR merged (conventional commits like `docs(m3): …`, `feat(m3/go): …`; no Claude-Session trailers), Codex review passed, annotated tag `mN`, `check-tags.sh mN` passes, worktree removed and branch deleted.

In this repo the README placeholder marker is `*Planned*`; "no `*Coming soon*` left" means no `*Planned*` rows left for the module.

## The Lesson Linter

`scripts/lint_lessons.py` (stdlib Python, run by `just lint-docs` and the CI `docs` job) checks every `docs/NN-*/LL-*.md` against the skeleton:

- line 1 `# Title`; line 3 `**Lesson N of M: <Module>**` with N = the file number and M = the number of lesson files in the folder; line 4 `**Ticketing Project**`
- every `> [!WARNING]` immediately followed by `> **Reality check (<slug>) —** <text>`
- exactly one `## K. See It: …` H2, at least one ```` ```mermaid ```` fence
- `Code: Python`, `Code: Go`, `Code: Rust` H2s, once each, in that order
- no `./` or `../` links; `**Next:**`, `**Previous:**` and `**Module Overview:**` links that resolve from the repo root
- every path in the `## Key Files Summary` table exists

For overviews: once any lesson is `Done`, `diagrams/hero.{mmd,svg,png,excalidraw}` must exist. Problems print as `path:line: message`, and the exit code is 1:

```text
docs/01-http-by-hand/02-BODIES-CONTENT-LENGTH-AND-CHUNKED.md:3: header says of 4 but the folder has 5 lesson file(s)
docs/01-http-by-hand/02-BODIES-CONTENT-LENGTH-AND-CHUNKED.md:212: link './03-KEEP-ALIVE-AND-PIPELINING.md' must be repo-root-relative (no ./ or ../)
```

Headings and links inside code fences are ignored, so bash comments starting with `##` are safe. `python3 scripts/lint_lessons.py --root PATH` lints another checkout. The link check (`lychee --offline --base-url file://<repo>/`) resolves every relative link from the repo root, the same rule the site sync uses. CI also renders every Mermaid fence with `mmdc`, so a diagram that does not parse fails the build.

## Author and Porter Ownership

Each module is built by an Author and a Porter working in the same worktree. Ownership is by path and by heading, so their commits never conflict.

| Role | Owns | Never touches |
|------|------|---------------|
| **Author** | `docs/NN-slug/00-OVERVIEW.md`; all lesson prose, Mermaid and `Code: Python` sections; `diagrams/hero.mmd`; `demos/NN/*/python/`; `apps/python/`; every `run.sh` and `see.sh`; shared artifacts (`db/migrations/`, `openapi/`, `proto/`, `infra/`); `PORT-SPEC.md` | `apps/go/`, `apps/rust/`, `demos/NN/*/{go,rust}/` |
| **Porter** (starts once `PORT-SPEC.md` is committed) | `apps/go/`, `apps/rust/`, `demos/NN/*/{go,rust}/`, their tests; in lessons, only the `Code: Go` and `Code: Rust` sections (and any `### Go` / `### Rust` subsections), edited by heading | Prose outside those sections, `apps/python/`, shared artifacts, `run.sh`/`see.sh` |

If a port needs a change to a shared artifact or a `run.sh`, the Porter asks the Author. The Author rebases last.

## Commits and Pull Requests

- Conventional commits with module scopes: `docs(m3): …`, `feat(m3/python): …`, `feat(m3/go): …`, `feat(m3/rust): …`, `fix(m3/rust): …`, `ci: …`, `chore: …`.
- No `Claude-Session:` trailers and no claude.ai links in commits or PR descriptions.
- One PR per module. The PR body summarises the Codex review and challenge, and lists any check that was run locally instead of in CI.
- CI must stay on the free tier: never add paid runners or paid services.

## Questions?

Open an issue if something is unclear or you need guidance on where to contribute.
