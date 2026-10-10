//! Ticketing service, Rust port.
//!
//! Python carries the narrative in every lesson; this port mirrors its names,
//! subcommands and behaviour. Module code lands in `src/<package>/` and is
//! exported from here.

/// Returns the app version (from `Cargo.toml`). Keep it equal to apps/python and apps/go.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// Returns what `ticketing version` prints; every port prints the same shape.
pub fn version_line() -> String {
    format!("ticketing {} (rust)", version())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_semver() {
        let parts: Vec<&str> = version().split('.').collect();
        assert_eq!(parts.len(), 3, "{} is not MAJOR.MINOR.PATCH", version());
        assert!(parts.iter().all(|p| p.parse::<u64>().is_ok()));
    }

    #[test]
    fn version_line_matches_other_ports() {
        assert_eq!(version_line(), format!("ticketing {} (rust)", version()));
    }
}
