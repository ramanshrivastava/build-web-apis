#!/usr/bin/env bash
# demos/00/05/run.sh LANG [--smoke] [ARGS...]: run the echo server in one language.
#
#   just demo 00/05 python --mode blocking       # serve on 127.0.0.1:9005
#   just demo 00/05 python --mode epoll          # extra args go to the demo
#   just demo 00/05 all --smoke                  # both modes, two clients each
#
# epoll is Linux-only, so on macOS this script re-runs itself inside the lab.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
lang="${1:?usage: run.sh python|go|rust [--smoke] [ARGS...]}"
shift

if [ "$(uname -s)" != Linux ]; then
  tty=-T
  if [ -t 0 ] && [ -t 1 ]; then tty=""; fi
  exec docker compose -f "$root/docker-compose.yml" run --rm $tty lab \
    bash demos/00/05/run.sh "$lang" "$@"
fi

skip_unported() { # a port the Porter has not written yet is skipped, loudly
  echo "run.sh: demos/00/05/$1 not ported yet (see PORT-SPEC.md); skipping $lang"
  exit 0
}

# go build and rustc write a temporary binary that the trap deletes. A Cargo build
# stays in Cargo's target directory: bin points there, and the trap never touches it.
tmpbin="${TMPDIR:-/tmp}/demo-00-05-$lang-$$"
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
      bin="${CARGO_TARGET_DIR:-$here/rust/target}/release/demo-00-05"
    else
      rustc --edition 2021 -O "$here/rust/main.rs" -o "$bin"
    fi
    "$bin" "$@" ;;
  *) echo "run.sh: LANG must be python, go or rust" >&2; exit 2 ;;
esac
