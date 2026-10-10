//! Smoke tests: the binary exists, dispatches, and agrees with the other ports.

use std::process::Command;

fn ticketing(args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_ticketing"))
        .args(args)
        .output()
        .expect("failed to run the ticketing binary")
}

#[test]
fn version_fn_matches_cargo() {
    assert_eq!(ticketing::version(), env!("CARGO_PKG_VERSION"));
}

#[test]
fn version_command_prints_shared_line() {
    let out = ticketing(&["version"]);
    assert!(out.status.success());
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        format!("ticketing {} (rust)\n", ticketing::version())
    );
}

#[test]
fn help_lists_version() {
    let out = ticketing(&["--help"]);
    assert!(out.status.success());
    assert!(String::from_utf8_lossy(&out.stdout).contains("  version"));
}

#[test]
fn no_args_is_usage_error() {
    let out = ticketing(&[]);
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).contains("usage: ticketing"));
}

#[test]
fn unknown_command_is_usage_error() {
    let out = ticketing(&["nope"]);
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).contains("unknown command \"nope\""));
}
