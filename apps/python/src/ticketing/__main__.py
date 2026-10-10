"""Entry point: `uv run ticketing <command> [args...]`.

One binary, many subcommands. Each module registers its subcommand with one
line in COMMANDS, so modules built in parallel never edit the same line. Old
subcommands keep working when new ones arrive: `rawhttp` (m1) still serves
`GET /events` after `api` (m2) lands beside it.
"""

from __future__ import annotations

import sys
from collections.abc import Callable

from ticketing.version import version_line

Command = Callable[[list[str]], int]


def cmd_version(args: list[str]) -> int:
    """Print the version line and exit 0."""
    print(version_line())
    return 0


# One line per module. The same names exist in apps/go and apps/rust.
COMMANDS: dict[str, Command] = {
    "version": cmd_version,
    # m1: "rawhttp": rawhttp.main,
    # m2: "api": api.main,
    # m3: "inventory-grpc": inventory.main,
    # m4: "worker": worker.main,
    # m7: "lb": lb.main,
}


def usage() -> str:
    """Return the help text listing every registered subcommand."""
    names = "\n".join(f"  {name}" for name in sorted(COMMANDS))
    return f"usage: ticketing <command> [args...]\n\ncommands:\n{names}"


def main(argv: list[str] | None = None) -> int:
    """Dispatch to a subcommand. Exit codes: 0 ok, 2 usage error."""
    args = sys.argv[1:] if argv is None else argv
    if not args:
        print(usage(), file=sys.stderr)
        return 2
    name, rest = args[0], args[1:]
    if name in {"-h", "--help", "help"}:
        print(usage())
        return 0
    command = COMMANDS.get(name)
    if command is None:
        print(f'ticketing: unknown command "{name}"\n\n{usage()}', file=sys.stderr)
        return 2
    return command(rest)


if __name__ == "__main__":
    raise SystemExit(main())
