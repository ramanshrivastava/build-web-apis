#!/usr/bin/env bash
# demos/00/06/run.sh LANG [--smoke] [ARGS...]: run the runtime-native echo server.
#
#   just demo 00/06 python             # asyncio on 127.0.0.1:9006
#   just demo 00/06 go                 # net + one goroutine per connection
#   just demo 00/06 rust               # tokio, one task per connection
#   just demo 00/06 all --smoke        # 50 concurrent clients per language
#
# All three runtimes are portable (epoll on Linux, kqueue on macOS), so this
# runs natively; the See It (strace, py-spy, GODEBUG, /proc) runs in the lab.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lang="${1:?usage: run.sh python|go|rust [--smoke] [ARGS...]}"
shift

skip_unported() { # a port the Porter has not written yet is skipped, loudly
  echo "run.sh: demos/00/06/$1 not ported yet (see PORT-SPEC.md); skipping $lang"
  exit 0
}

# go build and rustc write a temporary binary that the trap deletes. A Cargo build
# stays in Cargo's target directory: bin points there, and the trap never touches it.
tmpbin="${TMPDIR:-/tmp}/demo-00-06-$lang-$$"
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
      bin="${CARGO_TARGET_DIR:-$here/rust/target}/release/demo-00-06"
    else
      rustc --edition 2021 -O "$here/rust/main.rs" -o "$bin"
    fi
    "$bin" "$@" ;;
  *) echo "run.sh: LANG must be python, go or rust" >&2; exit 2 ;;
esac
