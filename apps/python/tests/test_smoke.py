"""Smoke tests: the binary exists, dispatches, and agrees with the other ports."""

import re

import pytest

from ticketing.__main__ import COMMANDS, main
from ticketing.version import VERSION, version_line


def test_version_is_semver() -> None:
    assert re.fullmatch(r"\d+\.\d+\.\d+", VERSION)


def test_version_command_prints_shared_line(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["version"]) == 0
    assert capsys.readouterr().out == f"ticketing {VERSION} (python)\n"
    assert version_line() == f"ticketing {VERSION} (python)"


def test_registry_has_version() -> None:
    assert "version" in COMMANDS


def test_help_lists_commands(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["--help"]) == 0
    out = capsys.readouterr().out
    for name in COMMANDS:
        assert f"  {name}" in out


def test_no_args_is_usage_error(capsys: pytest.CaptureFixture[str]) -> None:
    assert main([]) == 2
    assert "usage: ticketing" in capsys.readouterr().err


def test_unknown_command_is_usage_error(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["nope"]) == 2
    assert 'unknown command "nope"' in capsys.readouterr().err
