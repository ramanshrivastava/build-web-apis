//! `ticketing <command> [args...]`: the Rust port's single binary.
//!
//! One binary, many subcommands. Each module adds one arm to `dispatch` and
//! one name to `COMMANDS`, so modules built in parallel never edit the same
//! line. Old subcommands keep working when new ones arrive.

use std::process::ExitCode;

/// Registered subcommand names, one line per module (shown by `--help`).
const COMMANDS: &[&str] = &[
    "version",
    // m1: "rawhttp",
    // m2: "api",
    // m3: "inventory-grpc",
    // m4: "worker",
    // m7: "lb",
];

/// Runs a subcommand, or returns `None` if `name` is not registered.
fn dispatch(name: &str, args: &[String]) -> Option<u8> {
    let code = match name {
        "version" => cmd_version(args),
        // m1: "rawhttp" => ticketing::rawhttp::main(args),
        // m2: "api" => ticketing::api::main(args),
        // m3: "inventory-grpc" => ticketing::inventory::main(args),
        // m4: "worker" => ticketing::worker::main(args),
        // m7: "lb" => ticketing::lb::main(args),
        _ => return None,
    };
    Some(code)
}

fn cmd_version(_args: &[String]) -> u8 {
    println!("{}", ticketing::version_line());
    0
}

fn usage() -> String {
    let mut names = COMMANDS.to_vec();
    names.sort_unstable();
    let list: Vec<String> = names.iter().map(|n| format!("  {n}")).collect();
    format!(
        "usage: ticketing <command> [args...]\n\ncommands:\n{}",
        list.join("\n")
    )
}

/// Dispatches to a subcommand. Exit codes: 0 ok, 2 usage error.
fn run(args: &[String]) -> u8 {
    let Some((name, rest)) = args.split_first() else {
        eprintln!("{}", usage());
        return 2;
    };
    if matches!(name.as_str(), "-h" | "--help" | "help") {
        println!("{}", usage());
        return 0;
    }
    match dispatch(name, rest) {
        Some(code) => code,
        None => {
            eprintln!("ticketing: unknown command \"{name}\"\n\n{}", usage());
            2
        }
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    ExitCode::from(run(&args))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_listed_command_dispatches() {
        for name in COMMANDS {
            assert!(
                dispatch(name, &[]).is_some(),
                "{name} is listed but not dispatched"
            );
        }
    }

    #[test]
    fn unknown_command_does_not_dispatch() {
        assert!(dispatch("nope", &[]).is_none());
    }
}
