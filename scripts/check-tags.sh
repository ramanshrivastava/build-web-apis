#!/usr/bin/env bash
# Verify module tags. For each tag: check it out in a temporary worktree,
# migrate a fresh database, run `just test`, build all three ports, and start
# every subcommand that tag promised (old ones must keep working).
#
#   scripts/check-tags.sh            # every m* tag
#   scripts/check-tags.sh m1 m4      # only these
#
# Needs `just up` (postgres + redis) once a tag has migrations, plus uv, go,
# cargo, curl and nc. Tag table (cumulative):
#
#   tag      subcommands that must start          check
#   m0       version                              prints "ticketing X (<lang>)"
#   m1       + rawhttp                            GET /events -> 200 within 10 s
#   m2       + api                                GET /events -> 200 within 10 s
#   m3       + inventory-grpc                     TCP port accepts within 10 s
#   m4..m6   + worker                             still running after 3 s
#   m7..m8   + lb (in front of api)               GET /events -> 200 within 10 s
#
# CLI contract (CLAUDE.md): network subcommands take --addr HOST:PORT;
# lb also takes --upstream URL (repeatable).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BASE_DB_URL="${DATABASE_URL:-postgres://postgres:ticketing@localhost:5432/ticketing}"
export REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"
TIMEOUT="${CHECK_TAGS_TIMEOUT:-10}"
# Reuse the main checkout's cargo target dir so each tag does not rebuild deps.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/apps/rust/target}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-tags.XXXXXX")"
PIDS="" WORKTREES="" DATABASES="" RESULTS="" FAILED=0

cleanup() {
  local pid wt db
  for pid in $PIDS; do kill "$pid" 2>/dev/null || true; done
  for db in $DATABASES; do
    psql "$BASE_DB_URL" -X -q -c "DROP DATABASE IF EXISTS $db" >/dev/null 2>&1 || true
  done
  for wt in $WORKTREES; do git worktree remove --force "$wt" 2>/dev/null || true; done
  git worktree prune
  rm -rf "$WORK"
}
trap cleanup EXIT

record() { # tag lang check status
  RESULTS="$RESULTS$(printf '%-4s %-7s %-16s %s' "$1" "$2" "$3" "$4")"$'\n'
  if [ "$4" != PASS ]; then FAILED=1; fi
}

commands_for() { # tag -> subcommands that must start
  local n="${1#m}" cmds=""
  if [ "$n" -ge 1 ]; then cmds="$cmds rawhttp"; fi
  if [ "$n" -ge 2 ]; then cmds="$cmds api"; fi
  if [ "$n" -ge 3 ]; then cmds="$cmds inventory-grpc"; fi
  if [ "$n" -ge 4 ]; then cmds="$cmds worker"; fi
  if [ "$n" -ge 7 ]; then cmds="$cmds lb"; fi
  echo "$cmds"
}

wait_http() { # url seconds
  local deadline=$((SECONDS + $2)) code
  while [ "$SECONDS" -lt "$deadline" ]; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "$1" || true)"
    if [ "$code" = 200 ]; then return 0; fi
    sleep 0.2
  done
  return 1
}

wait_tcp() { # port seconds
  local deadline=$((SECONDS + $2))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if nc -z 127.0.0.1 "$1" 2>/dev/null; then return 0; fi
    sleep 0.2
  done
  return 1
}

start() { # log bin args... ; sets LAST_PID
  local log="$1"
  shift
  "$@" >"$log" 2>&1 &
  LAST_PID=$!
  PIDS="$PIDS $LAST_PID"
}

check_lang() { # tag lang bin base_port db_url
  local tag="$1" lang="$2" bin="$3" port="$4" db_url="$5" out cmd ok api_port=""
  if out="$("$bin" version 2>&1)" && [[ "$out" == "ticketing "*" ($lang)" ]]; then
    record "$tag" "$lang" version PASS
  else
    record "$tag" "$lang" version "FAIL: $out"
  fi
  for cmd in $(commands_for "$tag"); do
    port=$((port + 1))
    local log="$WORK/$tag-$lang-$cmd.log"
    ok=0
    case "$cmd" in
      rawhttp|api)
        DATABASE_URL="$db_url" start "$log" "$bin" "$cmd" --addr "127.0.0.1:$port"
        if wait_http "http://127.0.0.1:$port/events" "$TIMEOUT"; then ok=1; fi
        if [ "$cmd" = api ]; then api_port="$port"; fi
        ;;
      inventory-grpc)
        DATABASE_URL="$db_url" start "$log" "$bin" "$cmd" --addr "127.0.0.1:$port"
        if wait_tcp "$port" "$TIMEOUT"; then ok=1; fi
        ;;
      worker)
        DATABASE_URL="$db_url" start "$log" "$bin" "$cmd"
        sleep 3
        if kill -0 "$LAST_PID" 2>/dev/null; then ok=1; fi
        ;;
      lb)
        start "$log" "$bin" "$cmd" --addr "127.0.0.1:$port" --upstream "http://127.0.0.1:$api_port"
        if wait_http "http://127.0.0.1:$port/events" "$TIMEOUT"; then ok=1; fi
        ;;
    esac
    if [ "$ok" = 1 ]; then
      record "$tag" "$lang" "$cmd" PASS
    else
      record "$tag" "$lang" "$cmd" "FAIL (log: $(tail -n 3 "$log" | tr '\n' ' '))"
    fi
  done
}

check_tag() {
  local tag="$1" wt db_name db_url n
  if ! [[ "$tag" =~ ^m[0-8]$ ]]; then record "$tag" - tag "FAIL: not m0..m8"; return; fi
  if ! git rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null; then
    record "$tag" - tag "FAIL: no such tag"
    return
  fi
  echo "check-tags: === $tag"
  wt="$WORK/wt-$tag"
  git worktree add --detach --quiet "$wt" "$tag"
  WORKTREES="$WORKTREES $wt"
  db_url="$BASE_DB_URL"

  if compgen -G "$wt/db/migrations/*.sql" >/dev/null; then
    db_name="ticketing_check_${tag}_$$"
    db_url="${BASE_DB_URL%/*}/$db_name"
    if psql "$BASE_DB_URL" -X -q -v ON_ERROR_STOP=1 -c "CREATE DATABASE $db_name" \
       && DATABASES="$DATABASES $db_name" \
       && DATABASE_URL="$db_url" "$wt/scripts/migrate.sh"; then
      record "$tag" - migrate PASS
    else
      record "$tag" - migrate "FAIL (is 'just up' running?)"
      return
    fi
  fi

  if (cd "$wt" && DATABASE_URL="$db_url" just test); then
    record "$tag" - "just test" PASS
  else
    record "$tag" - "just test" FAIL
    return
  fi

  (cd "$wt/apps/python" && uv sync --quiet --locked)
  (cd "$wt/apps/go" && go build -o "$WORK/$tag-go/ticketing" ./cmd/ticketing)
  (cd "$wt/apps/rust" && cargo build --quiet --locked)

  n="${tag#m}"
  check_lang "$tag" python "$wt/apps/python/.venv/bin/ticketing" $((18000 + n * 100)) "$db_url"
  check_lang "$tag" go "$WORK/$tag-go/ticketing" $((18030 + n * 100)) "$db_url"
  check_lang "$tag" rust "$CARGO_TARGET_DIR/debug/ticketing" $((18060 + n * 100)) "$db_url"

  for pid in $PIDS; do kill "$pid" 2>/dev/null || true; done
  PIDS=""
}

if [ "$#" -gt 0 ]; then
  tags="$*"
else
  tags="$(git tag --list 'm[0-9]*' | sort | tr '\n' ' ')"
fi
if [ -z "${tags// /}" ]; then
  echo "check-tags: no m* tags yet; nothing to check"
  exit 0
fi

for tag in $tags; do check_tag "$tag"; done

echo
echo "check-tags: results"
printf '%s' "$RESULTS"
if [ "$FAILED" = 1 ]; then
  echo "check-tags: FAILED" >&2
  exit 1
fi
echo "check-tags: all passed"
