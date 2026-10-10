# Build Web APIs: one entry point for every workflow. `just` lists recipes.
# Keep this file compatible with just 1.21 (the lab image's apt version).

set shell := ["bash", "-euo", "pipefail", "-c"]
# Pass recipe arguments as "$@" too, so quoted ARGS survive (just lab bash -c '...').
set positional-arguments := true

export DATABASE_URL := env_var_or_default("DATABASE_URL", "postgres://postgres:ticketing@localhost:5432/ticketing")
export REDIS_URL := env_var_or_default("REDIS_URL", "redis://localhost:6379/0")

# List recipes
default:
    @just --list --unsorted

# --- services ---------------------------------------------------------------

# Start postgres 16 + redis 7 and wait until both are healthy
up:
    docker compose up -d --wait postgres redis

# Stop services (keeps the data volume; `docker compose down -v` wipes it)
down:
    docker compose down

# Shell in the Linux lab (tcpdump, strace, ss, perf, wrk, k6), or run ARGS there
lab *ARGS:
    docker compose run --rm --build lab "$@"

# Apply db/migrations/*.sql in order (add --seed to load db/seed.sql)
migrate *ARGS:
    scripts/migrate.sh "$@"

# --- tests ------------------------------------------------------------------

# Test all three ports (Python, then Go, then Rust)
test: test-python test-go test-rust

# pytest
test-python:
    cd apps/python && uv run pytest

# go test with the race detector
test-go:
    cd apps/go && go test -race ./...

# cargo test (unit + integration)
test-rust:
    cd apps/rust && cargo test

# --- lint -------------------------------------------------------------------

# Lint everything: ruff, golangci-lint, clippy, lessons and links
lint: lint-python lint-go lint-rust lint-docs

# ruff check + format check
lint-python:
    cd apps/python && uv run ruff check . && uv run ruff format --check .

# gofmt + golangci-lint (falls back to go vet if golangci-lint is missing)
lint-go:
    #!/usr/bin/env bash
    set -euo pipefail
    cd apps/go
    unformatted="$(gofmt -l .)"
    if [ -n "$unformatted" ]; then echo "lint-go: run gofmt -w on: $unformatted" >&2; exit 1; fi
    if command -v golangci-lint >/dev/null 2>&1; then
      golangci-lint run ./...
    else
      echo "lint-go: golangci-lint not installed (brew install golangci-lint); running go vet only" >&2
      go vet ./...
    fi

# rustfmt + clippy with warnings as errors
lint-rust:
    cd apps/rust && cargo fmt --check && cargo clippy --all-targets --locked -- -D warnings

# Lesson skeleton linter + offline link check, links relative to each file (lychee or its image)
lint-docs:
    #!/usr/bin/env bash
    set -euo pipefail
    python3 scripts/lint_lessons.py
    files="$(git ls-files --cached --others --exclude-standard '*.md')"
    if command -v lychee >/dev/null 2>&1; then
      lychee --offline --no-progress $files
    elif docker info >/dev/null 2>&1; then
      docker run --rm -v "$PWD:/input:ro" -w /input lycheeverse/lychee:0.24.2 \
        --offline --no-progress $files
    else
      echo "lint-docs: neither lychee nor docker available; link check skipped" >&2
    fi

# --- lessons ----------------------------------------------------------------

# Run a lesson's demo: just demo 01/04 [python|go|rust|all] [--smoke]
demo LESSON LANG='all' *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{LESSON}}" =~ ^[0-9]{2}/[0-9]{2}$ ]] || { echo "demo: want MM/LL, e.g. 01/04" >&2; exit 2; }
    run="demos/{{LESSON}}/run.sh"
    [ -f "$run" ] || { echo "demo: $run does not exist yet (lesson not built)" >&2; exit 1; }
    if [ "{{LANG}}" = all ]; then langs="python go rust"; else langs="{{LANG}}"; fi
    for lang in $langs; do
      case "$lang" in python|go|rust) ;; *) echo "demo: LANG must be python, go, rust or all" >&2; exit 2 ;; esac
      echo "== demo {{LESSON}} $lang {{FLAGS}}"
      bash "$run" "$lang" {{FLAGS}}
    done

# Run a lesson's See It: inside the lab on macOS, directly on Linux (SEE_IN_LAB=1 forces the lab)
see LESSON:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{LESSON}}" =~ ^[0-9]{2}/[0-9]{2}$ ]] || { echo "see: want MM/LL, e.g. 03/04" >&2; exit 2; }
    script="demos/{{LESSON}}/see.sh"
    [ -f "$script" ] || { echo "see: $script does not exist yet (lesson not built)" >&2; exit 1; }
    if [ "$(uname -s)" = Linux ] && [ "${SEE_IN_LAB:-0}" != 1 ]; then
      bash "$script"
    else
      docker compose run --rm --build -T lab bash "$script"
    fi

# Smoke-run every demos/*/*/run.sh in all three languages, 60 s cap each
demo-smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    runs=(demos/*/*/run.sh)
    if [ "${#runs[@]}" -eq 0 ]; then
      echo "demo-smoke: no demos yet (demos/*/*/run.sh); nothing to run"
      exit 0
    fi
    if command -v timeout >/dev/null 2>&1; then cap="timeout 60"
    elif command -v gtimeout >/dev/null 2>&1; then cap="gtimeout 60"
    else cap=""; echo "demo-smoke: timeout(1) not found; running without the 60 s cap" >&2
    fi
    failed=""
    for run in "${runs[@]}"; do
      for lang in python go rust; do
        echo "== $run $lang --smoke"
        $cap bash "$run" "$lang" --smoke || failed="$failed $run:$lang"
      done
    done
    if [ -n "$failed" ]; then echo "demo-smoke: FAILED:$failed" >&2; exit 1; fi
    echo "demo-smoke: ${#runs[@]} demo(s) x 3 languages passed"

# --- release ----------------------------------------------------------------

# Verify module tags (default: every m* tag): tests pass, subcommands start
check-tags *TAGS:
    scripts/check-tags.sh "$@"

# Everything CI checks, run locally (the fallback when Actions minutes run out)
ci-local: lint test demo-smoke check-tags

# Tag a merged module from a clean main, verify it, never push: just tag m3
tag MN:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{MN}}" =~ ^m[0-8]$ ]] || { echo "tag: want m0..m8, got '{{MN}}'" >&2; exit 2; }
    [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "tag: check out main first" >&2; exit 1; }
    git diff --quiet && git diff --cached --quiet || { echo "tag: working tree is dirty" >&2; exit 1; }
    if git rev-parse -q --verify "refs/tags/{{MN}}" >/dev/null; then echo "tag: {{MN}} already exists" >&2; exit 1; fi
    git tag -a "{{MN}}" -m "Module $(echo {{MN}} | tr -d m) complete"
    if ! scripts/check-tags.sh "{{MN}}"; then
      git tag -d "{{MN}}" >/dev/null
      echo "tag: check-tags failed; {{MN}} removed" >&2
      exit 1
    fi
    echo "tag: {{MN}} verified. Push it yourself: git push origin {{MN}}"
