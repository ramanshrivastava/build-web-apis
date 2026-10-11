#!/usr/bin/env bash
# demos/00/02/run.sh LANG [--smoke] [ARGS...]: send a hand-built DNS query in one language.
#
#   just demo 00/02 python                         # A record for example.com
#   just demo 00/02 python --type TXT google.com   # extra args go to the demo
#   just demo 00/02 all --smoke                    # needs network; skipped when CI_OFFLINE=1
#
# Plain UDP and TCP sockets, so it runs natively on macOS and Linux.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lang="${1:?usage: run.sh python|go|rust [--smoke] [ARGS...]}"
shift

# The one Module 0 demo that needs the internet (a real resolver).
if [ "${1:-}" = --smoke ] && [ "${CI_OFFLINE:-0}" = 1 ]; then
  echo "skip: demo 00/02 needs external network (CI_OFFLINE=1)"
  exit 0
fi

skip_unported() { # a port the Porter has not written yet is skipped, loudly
  echo "run.sh: demos/00/02/$1 not ported yet (see PORT-SPEC.md); skipping $lang"
  exit 0
}

# go build and rustc write a temporary binary that the trap deletes. A Cargo build
# stays in Cargo's target directory: bin points there, and the trap never touches it.
tmpbin="${TMPDIR:-/tmp}/demo-00-02-$lang-$$"
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
      bin="${CARGO_TARGET_DIR:-$here/rust/target}/release/demo-00-02"
    else
      rustc --edition 2021 -O "$here/rust/main.rs" -o "$bin"
    fi
    "$bin" "$@" ;;
  *) echo "run.sh: LANG must be python, go or rust" >&2; exit 2 ;;
esac
