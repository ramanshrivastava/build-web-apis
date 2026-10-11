//! Lesson 0.4 demo (Rust): neveraccept, a server that listens and never calls accept().
//!
//! The kernel completes TCP handshakes without the process: a finished
//! connection waits in the listener's accept queue until accept() takes it.
//! With nobody calling accept(), the queue fills (Linux holds backlog + 1) and
//! later clients sit in SYN_SENT. std's `TcpListener::bind` always calls
//! listen(fd, 128), so the listener and the clients are built from libc calls,
//! each wrapped in `unsafe` and checked for -1. Linux only.
//!
//!     cargo run --release                          # backlog 4, 8 clients, hold 30 s for ss
//!     cargo run --release -- --hold 5 --drain      # then accept everything and close it
//!     cargo run --release -- --smoke               # assert 5 connected, 3 pending, all 8 drained

use std::io;
use std::mem;
use std::net::Ipv4Addr;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::process::ExitCode;
use std::thread::sleep;
use std::time::{Duration, Instant};

/// libc calls return -1 and set errno on failure; turn that into an io::Error.
fn check(ret: libc::c_int) -> io::Result<libc::c_int> {
    if ret < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(ret)
}

fn loopback(port: u16) -> libc::sockaddr_in {
    let mut addr: libc::sockaddr_in = unsafe { mem::zeroed() };
    addr.sin_family = libc::AF_INET as libc::sa_family_t;
    addr.sin_port = port.to_be(); // network byte order
    addr.sin_addr.s_addr = u32::from(Ipv4Addr::LOCALHOST).to_be();
    addr
}

const ADDR_LEN: libc::socklen_t = mem::size_of::<libc::sockaddr_in>() as libc::socklen_t;

fn tcp_socket() -> io::Result<OwnedFd> {
    let fd = check(unsafe { libc::socket(libc::AF_INET, libc::SOCK_STREAM, 0) })?;
    Ok(unsafe { OwnedFd::from_raw_fd(fd) }) // closed when dropped
}

fn set_nonblocking(fd: RawFd) -> io::Result<()> {
    let flags = check(unsafe { libc::fcntl(fd, libc::F_GETFL) })?;
    check(unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) })?;
    Ok(())
}

fn listen(port: u16, backlog: i32) -> io::Result<OwnedFd> {
    let listener = tcp_socket()?;
    let fd = listener.as_raw_fd();
    // TIME_WAIT sockets from a previous --drain still hold the port; allow rebinding.
    let one: libc::c_int = 1;
    let (opt, len) = (
        (&one as *const libc::c_int).cast(),
        mem::size_of::<libc::c_int>() as libc::socklen_t,
    );
    check(unsafe { libc::setsockopt(fd, libc::SOL_SOCKET, libc::SO_REUSEADDR, opt, len) })?;
    let addr = loopback(port);
    check(unsafe { libc::bind(fd, (&addr as *const libc::sockaddr_in).cast(), ADDR_LEN) })?;
    // The accept queue's limit, exactly as given (capped by net.core.somaxconn).
    check(unsafe { libc::listen(fd, backlog) })?;
    Ok(listener)
}

/// Open `count` sockets and start a non-blocking connect() on each.
fn start_clients(port: u16, count: usize) -> io::Result<Vec<OwnedFd>> {
    let mut clients = Vec::new();
    let addr = loopback(port);
    for _ in 0..count {
        let client = tcp_socket()?;
        set_nonblocking(client.as_raw_fd())?;
        // connect() returns at once with EINPROGRESS; the handshake goes on in the kernel.
        let ret = unsafe {
            libc::connect(
                client.as_raw_fd(),
                (&addr as *const libc::sockaddr_in).cast(),
                ADDR_LEN,
            )
        };
        if let Err(e) = check(ret) {
            if e.raw_os_error() != Some(libc::EINPROGRESS) {
                return Err(e);
            }
        }
        clients.push(client);
    }
    Ok(clients)
}

/// A non-blocking connect has finished when the socket is writable with SO_ERROR 0.
fn connected(fd: RawFd) -> bool {
    let mut pfd = libc::pollfd {
        fd,
        events: libc::POLLOUT,
        revents: 0,
    };
    if unsafe { libc::poll(&mut pfd, 1, 0) } <= 0 {
        return false; // timeout 0: look, do not wait
    }
    let (mut so_error, mut len) = (
        0 as libc::c_int,
        mem::size_of::<libc::c_int>() as libc::socklen_t,
    );
    let out = (&mut so_error as *mut libc::c_int).cast();
    let ret = unsafe { libc::getsockopt(fd, libc::SOL_SOCKET, libc::SO_ERROR, out, &mut len) };
    ret == 0 && so_error == 0
}

fn local_port(fd: RawFd) -> u16 {
    let (mut addr, mut len) = (loopback(0), ADDR_LEN);
    unsafe { libc::getsockname(fd, (&mut addr as *mut libc::sockaddr_in).cast(), &mut len) };
    u16::from_be(addr.sin_port)
}

fn report(clients: &[OwnedFd], backlog: i32) -> usize {
    let mut done = 0;
    for (i, client) in clients.iter().enumerate() {
        let number = i + 1;
        let port = local_port(client.as_raw_fd());
        if connected(client.as_raw_fd()) {
            done += 1;
            println!("client {number}: connected from port {port} (waiting in the accept queue)");
        } else {
            println!("client {number}: pending from port {port} (SYN_SENT: no SYN-ACK yet)");
        }
    }
    let pending = clients.len() - done;
    println!(
        "result: {done} connected, {pending} pending; the accept queue holds backlog+1 = {}",
        backlog + 1
    );
    done
}

/// Accept for up to `limit`, closing each connection server-side first.
fn drain(listener: &OwnedFd, expected: usize, limit: Duration) -> io::Result<usize> {
    set_nonblocking(listener.as_raw_fd())?;
    let (mut accepted, started) = (0, Instant::now());
    while accepted < expected {
        let elapsed = started.elapsed();
        if elapsed >= limit {
            break;
        }
        let (mut peer, mut len) = (loopback(0), ADDR_LEN);
        let ret = unsafe {
            libc::accept(
                listener.as_raw_fd(),
                (&mut peer as *mut libc::sockaddr_in).cast(),
                &mut len,
            )
        };
        let fd = match check(ret) {
            Ok(fd) => unsafe { OwnedFd::from_raw_fd(fd) },
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                sleep(Duration::from_millis(50)); // queue empty; a retransmitted SYN may still arrive
                continue;
            }
            Err(e) => return Err(e),
        };
        accepted += 1;
        let port = u16::from_be(peer.sin_port);
        let at = elapsed.as_secs_f64();
        println!(
            "drain: accept() -> fd {} from port {port} at +{at:.1} s",
            fd.as_raw_fd()
        );
        drop(fd); // close(): the server closes first, so the server side goes to TIME_WAIT
    }
    println!("drain: accepted {accepted}; closed first, so they sit in TIME_WAIT (60 s)");
    Ok(accepted)
}

fn run(
    port: u16,
    backlog: i32,
    count: usize,
    hold: f64,
    do_drain: bool,
) -> io::Result<(usize, usize)> {
    let listener = listen(port, backlog)?;
    println!(
        "neveraccept: listening on 127.0.0.1:{port}, backlog {backlog}; accept() is not called"
    );
    let clients = start_clients(port, count)?;
    sleep(Duration::from_millis(500)); // let the handshakes that can complete, complete
    let done = report(&clients, backlog);
    if hold > 0.0 {
        // f64's Display prints 30 and 2.5, like Python's {hold:g}.
        println!("holding {hold} s: try  ss -lnt 'sport = :{port}'");
        sleep(Duration::from_secs_f64(hold));
    }
    let drained = if do_drain {
        drain(&listener, count, Duration::from_secs(4))?
    } else {
        0
    };
    drop(clients); // close every client, then the listener
    drop(listener);
    Ok((done, drained))
}

/// The value after a flag, parsed; a usage error if it is missing or malformed.
fn value<T: std::str::FromStr>(
    args: &mut impl Iterator<Item = String>,
    flag: &str,
) -> Result<T, String> {
    let raw = args.next().ok_or_else(|| format!("{flag} needs a value"))?;
    raw.parse()
        .map_err(|_| format!("bad value for {flag}: {raw}"))
}

struct Args {
    port: u16,
    backlog: i32,
    clients: usize,
    hold: f64,
    drain: bool,
    smoke: bool,
}

fn parse_args() -> Result<Args, String> {
    let mut parsed = Args {
        port: 9004,
        backlog: 4,
        clients: 8,
        hold: 30.0,
        drain: false,
        smoke: false,
    };
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--port" => parsed.port = value(&mut args, &arg)?,
            "--backlog" => parsed.backlog = value(&mut args, &arg)?,
            "--clients" => parsed.clients = value(&mut args, &arg)?,
            "--hold" => parsed.hold = value(&mut args, &arg)?,
            "--drain" => parsed.drain = true,
            "--smoke" => parsed.smoke = true,
            _ => return Err(format!("unexpected argument {arg}")),
        }
    }
    Ok(parsed)
}

fn main() -> ExitCode {
    let args = match parse_args() {
        Ok(args) => args,
        Err(msg) => {
            eprintln!("neveraccept: {msg}");
            return ExitCode::from(2);
        }
    };
    if !cfg!(target_os = "linux") {
        println!("neveraccept: the backlog+1 rule is Linux's; run it in the lab: just demo 00/04");
        return ExitCode::from(2);
    }
    let result = if args.smoke {
        run(args.port, 4, 8, 0.0, true)
    } else {
        run(args.port, args.backlog, args.clients, args.hold, args.drain)
    };
    let (done, drained) = match result {
        Ok(counts) => counts,
        Err(e) => {
            println!("neveraccept: {e}");
            return ExitCode::FAILURE;
        }
    };
    if !args.smoke {
        return ExitCode::SUCCESS;
    }
    if done == 5 && drained == 8 {
        println!("smoke: OK, 5 waited in the accept queue, 3 were dropped, all 8 drained");
        return ExitCode::SUCCESS;
    }
    println!("smoke: FAIL, expected 5 connected and 8 drained, got {done} and {drained}");
    ExitCode::FAILURE
}
