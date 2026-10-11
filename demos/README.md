# Demos

Every lesson starts with a demo: one small, single-file program per language that isolates the lesson's mechanism, plus two scripts, one that runs it and one that observes it. Demos are not the app. The app (`apps/`) grows module by module; a demo stays small enough to read in one sitting, and it keeps working after the lesson that introduced it.

## Layout Contract

```
demos/<mm>/<ll>/
├── README.md          # what the demo shows, how to run it, what to look for
├── python/main.py     # Python 3.12, stdlib unless the lesson is about a library
├── go/main.go         # package main
├── rust/main.rs       # a single file; std-only demos build with rustc
├── run.sh             # run.sh LANG [--smoke]
└── see.sh             # the lesson's See It, reproducible; declares EXPECT=
```

- `<mm>` is the module number (`00`–`08`) and `<ll>` the lesson number (`01`–`06`), both two digits, matching `docs/<mm>-<slug>/<ll>-<TITLE>.md`. Lesson 3.4's demo lives in `demos/03/04/`.
- **Dependencies.** Prefer the standard library. When a demo needs a library, keep the single file and add the smallest manifest beside it: PEP 723 inline metadata in `main.py` (run with `uv run`), a `go/go.mod`, or a `rust/Cargo.toml` with `[[bin]] path = "main.rs"`.
- **Same behaviour in all three languages**: the same flags, ports and output lines, so `see.sh` can observe any of them.
- **No external network**, except lessons 0.2 (DNS) and 3.6 (QUIC), which skip in smoke mode when `CI_OFFLINE=1`.

## `run.sh LANG [--smoke]`

- `LANG` is `python`, `go` or `rust`. `just demo <mm>/<ll> [LANG] [--smoke]` calls it once per language (`all` by default).
- Without `--smoke`, run the demo the way the lesson describes, interactively if the lesson needs that.
- With `--smoke`, run a short, self-checking version: exit 0 on success, non-zero on failure, in under 60 s. `just demo-smoke` runs every `demos/*/*/run.sh` in all three languages and kills any run at 60 s.
- Work from any directory: resolve paths from the script's own location.

```bash
#!/usr/bin/env bash
# demos/<mm>/<ll>/run.sh LANG [--smoke]: run this lesson's demo in one language.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lang="${1:?usage: run.sh python|go|rust [--smoke]}"
smoke=""
if [ "${2:-}" = --smoke ]; then smoke="--smoke"; fi
# Network demos (0.2, 3.6) only:
# if [ -n "$smoke" ] && [ "${CI_OFFLINE:-0}" = 1 ]; then echo "skip: needs external network"; exit 0; fi
# rustc writes a temporary binary that the trap deletes. A Cargo build stays in Cargo's
# target directory: bin points there, and the trap never touches it.
tmpbin="${TMPDIR:-/tmp}/demo-$$"
trap 'rm -f "$tmpbin"' EXIT
bin="$tmpbin"
case "$lang" in
  python) python3 "$here/python/main.py" ${smoke:+"$smoke"} ;;
  go)     go run "$here/go/main.go" ${smoke:+"$smoke"} ;;
  rust)
    if [ -f "$here/rust/Cargo.toml" ]; then
      cargo build --quiet --release --manifest-path "$here/rust/Cargo.toml"
      bin="${CARGO_TARGET_DIR:-$here/rust/target}/release/demo-<mm>-<ll>"
    else
      rustc --edition 2021 -O "$here/rust/main.rs" -o "$bin"
    fi
    "$bin" ${smoke:+"$smoke"} ;;
  *) echo "run.sh: LANG must be python, go or rust" >&2; exit 2 ;;
esac
```

The Module 0 `run.sh` files are the worked examples: they also pass extra arguments through, build Go modules with build tags (`go/go.mod`), re-run Linux-only demos inside the lab on macOS, and skip `--smoke` for network demos when `CI_OFFLINE=1`.

## `see.sh`: the reproducible See It

- Declares `EXPECT='<regex>'` near the top. It **exits non-zero if no output line matches**, so a See It that silently stops showing the mechanism fails CI.
- Sources `scripts/see/common.sh`, which provides `require_tool`, `see_run` (show output and log it), `see_log`, `start_bg` (runs a command in its own process group and records its pid in `$SEE_BG_PID`), `wait_bg` and `stop_bg` (bounded waits; TERM then KILL to the whole process group, sent through `$SUDO`, until the group is empty), `wait_port` and `expect_match`, plus `$SUDO` (empty as root in the lab, `sudo -n` on the CI runner) and `$SEE_ROOT`. `scripts/see/selftest.sh` checks that the helpers leave no survivors.
- Starts **every** background process with `start_bg`, including tracers such as `strace`, pipelines (`start_bg bash -c '… | nc …'`) and root-only tools (`start_bg $SUDO timeout 5 tcpdump …`). Root-only observation commands also run under `$SUDO` in the foreground (`see_run $SUDO iptables -S …`), so the same script works as root in the lab and through passwordless sudo on the CI runner. On any exit, `see_cleanup` stops each one and its children with a bounded TERM-then-KILL, so a failing `see.sh` never hangs or leaves a server behind.
- Replays the lesson's See It commands. The lesson's printed commands and `see.sh` must agree; the Codex challenge pass re-runs both.
- Runs via `just see <mm>/<ll>`: inside the lab on macOS, directly on Linux (`SEE_IN_LAB=1` forces the lab).

```bash
#!/usr/bin/env bash
# demos/00/04/see.sh: the accept queue fills while nobody calls accept().
EXPECT='^LISTEN +[1-9]'
source "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/see/common.sh"
require_tool ss python3 nc
start_bg python3 "$SEE_ROOT/demos/00/04/python/main.py" --port 9004
wait_port 9004
for _ in 1 2 3; do nc -z 127.0.0.1 9004; done
see_run ss -lnt 'sport = :9004'
expect_match
```

`expect_match` prints `see: OK, matched /<regex>/: <line>` or fails with `see: FAIL, no output line matched /<regex>/`.

## Status

Module 0's six demos exist, in all three languages: `demos/00/01` (an `AF_PACKET` sniffer) through `demos/00/06` (one echo server on asyncio, goroutines and tokio). `just demo-smoke` runs all of them. Module 1's demos (`demos/01/`) are next.
