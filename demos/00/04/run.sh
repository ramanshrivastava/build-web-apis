#!/usr/bin/env bash
# demos/00/04/run.sh LANG [--smoke] [ARGS...]: run neveraccept in one language.
#
#   just demo 00/04 python                       # backlog 4, 8 clients, hold 30 s
#   just demo 00/04 python --hold 5 --drain      # extra args go to the demo
#   just demo 00/04 all --smoke                  # 5 queued, 3 dropped, all 8 drained
#
# The numbers (the queue holds backlog+1) are Linux's, so on macOS this script
# re-runs itself inside the lab container.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
lang="${1:?usage: run.sh python|go|rust [--smoke] [ARGS...]}"
shift

if [ "$(uname -s)" != Linux ]; then
  tty=-T
  if [ -t 0 ] && [ -t 1 ]; then tty=""; fi
  exec docker compose -f "$root/docker-compose.yml" run --rm $tty lab \
    bash demos/00/04/run.sh "$lang" "$@"
fi

skip_unported() { # a port the Porter has not written yet is skipped, loudly
  echo "run.sh: demos/00/04/$1 not ported yet (see PORT-SPEC.md); skipping $lang"
  exit 0
}

# go build and rustc write a temporary binary that the trap deletes. A Cargo build
# stays in Cargo's target directory: bin points there, and the trap never touches it.
tmpbin="${TMPDIR:-/tmp}/demo-00-04-$lang-$$"
trap 'rm -f "$tmpbin"' EXIT
bin="$tmpbin"
case "$lang" in
  python)
    python3 "$here/python/main.py" "$@" ;;
  go)
    [ -f "$here/go/main.go" ] || skip_unported go/main.go
    if [ -f "$here/go/go.mod" ]; then (cd "$here/go" && go build -o "$bin" .)
    else go build -o "$bin" "$here/go/main.go"; fi
    "$bin" "$@" ;;
  rust)
    [ -f "$here/rust/main.rs" ] || skip_unported rust/main.rs
    if [ -f "$here/rust/Cargo.toml" ]; then
      cargo build --quiet --release --manifest-path "$here/rust/Cargo.toml"
      bin="${CARGO_TARGET_DIR:-$here/rust/target}/release/demo-00-04"
    else
      rustc --edition 2021 -O "$here/rust/main.rs" -o "$bin"
    fi
    "$bin" "$@" ;;
  *) echo "run.sh: LANG must be python, go or rust" >&2; exit 2 ;;
esac
