"""The app version, identical across the Python, Go and Rust ports."""

VERSION = "0.0.0"


def version_line() -> str:
    """Return the line `ticketing version` prints (same shape in every port)."""
    return f"ticketing {VERSION} (python)"
