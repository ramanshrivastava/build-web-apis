//! Lesson 0.5 demo (Rust): an echo server two ways, blocking and with raw epoll.
//!
//! --mode blocking: socket(), bind(), listen(), then accept() and read()/write()
//! one client at a time. While it is blocked in read() on client A, client B's
//! connection waits in the accept queue: head-of-line blocking.
//!
//! --mode epoll: every fd is O_NONBLOCK and one epoll instance says which fds
//! are ready. read() returns EAGAIN when a socket is drained; that is the
//! signal to go back to epoll_wait(), not an error. One thread serves every client.
//!
//! No std::net::TcpListener and no mio on the server side: both would hide the
//! calls this lesson is about. Every call is the libc crate on integer fds,
//! inside `unsafe`, returning -1 plus errno on failure, and each line printed
//! names the syscall just made, so the output lines up with strace. Linux only.
//!
//!     cargo run --release -- --mode blocking     # serve on 127.0.0.1:9005
//!     cargo run --release -- --mode epoll
//!     cargo run --release -- --smoke             # both modes, two clients each, self-checking

// The fd helpers are portable; socket setup, accept4() and epoll are Linux-only.
#![cfg_attr(not(target_os = "linux"), allow(dead_code, unused_imports))]

use std::collections::HashMap;
use std::ffi::CStr;
use std::io::{self, Read, Write};
use std::mem;
use std::net::{Ipv4Addr, TcpStream};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::process::ExitCode;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

const BACKLOG: libc::c_int = 16;
const ADDR_LEN: libc::socklen_t = mem::size_of::<libc::sockaddr_in>() as libc::socklen_t;

/// libc calls return -1 and set errno on failure; turn that into an io::Error.
fn check(ret: libc::c_int) -> io::Result<libc::c_int> {
    if ret < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(ret)
}

/// read() and write() return a byte count (ssize_t), or -1 with errno.
fn check_len(ret: libc::ssize_t) -> io::Result<usize> {
    if ret < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(ret as usize)
}

fn loopback(port: u16) -> libc::sockaddr_in {
    let mut addr: libc::sockaddr_in = unsafe { mem::zeroed() };
    addr.sin_family = libc::AF_INET as libc::sa_family_t;
    addr.sin_port = port.to_be(); // network byte order
    addr.sin_addr.s_addr = u32::from(Ipv4Addr::LOCALHOST).to_be();
    addr
}

fn local_port(fd: RawFd) -> u16 {
    let (mut addr, mut len) = (loopback(0), ADDR_LEN);
    unsafe { libc::getsockname(fd, (&mut addr as *mut libc::sockaddr_in).cast(), &mut len) };
    u16::from_be(addr.sin_port)
}

/// O_NONBLOCK with fcntl(F_GETFL) + fcntl(F_SETFL); CPython uses ioctl(FIONBIO).
fn set_nonblocking(fd: RawFd) -> io::Result<()> {
    let flags = check(unsafe { libc::fcntl(fd, libc::F_GETFL) })?;
    check(unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) })?;
    Ok(())
}

fn read(fd: RawFd, buf: &mut [u8]) -> io::Result<usize> {
    check_len(unsafe { libc::read(fd, buf.as_mut_ptr().cast(), buf.len()) })
}

fn write(fd: RawFd, buf: &[u8]) -> io::Result<usize> {
    check_len(unsafe { libc::write(fd, buf.as_ptr().cast(), buf.len()) })
}

/// The errno's name and text, like the Python demo: "EADDRINUSE (Address already in use)".
fn describe(err: &io::Error) -> String {
    let Some(code) = err.raw_os_error() else {
        return err.to_string();
    };
    let name = match code {
        libc::EACCES => "EACCES",
        libc::EADDRINUSE => "EADDRINUSE",
        libc::EADDRNOTAVAIL => "EADDRNOTAVAIL",
        libc::EBADF => "EBADF",
        libc::ECONNRESET => "ECONNRESET",
        libc::EINVAL => "EINVAL",
        libc::EMFILE => "EMFILE",
        libc::ENFILE => "ENFILE",
        libc::EPIPE => "EPIPE",
        _ => return format!("{code} ({err})"),
    };
    let text = unsafe { CStr::from_ptr(libc::strerror(code)) };
    format!("{name} ({})", text.to_string_lossy())
}

#[cfg(target_os = "linux")]
fn make_listener(port: u16, nonblocking: bool) -> io::Result<OwnedFd> {
    let fd =
        check(unsafe { libc::socket(libc::AF_INET, libc::SOCK_STREAM | libc::SOCK_CLOEXEC, 0) })?;
    let listener = unsafe { OwnedFd::from_raw_fd(fd) }; // closed on drop if a step below fails
    let one: libc::c_int = 1;
    let (opt, len) = (
        (&one as *const libc::c_int).cast(),
        mem::size_of::<libc::c_int>() as libc::socklen_t,
    );
    check(unsafe { libc::setsockopt(fd, libc::SOL_SOCKET, libc::SO_REUSEADDR, opt, len) })?;
    let addr = loopback(port);
    check(unsafe { libc::bind(fd, (&addr as *const libc::sockaddr_in).cast(), ADDR_LEN) })?;
    check(unsafe { libc::listen(fd, BACKLOG) })?;
    if nonblocking {
        set_nonblocking(fd)?;
    }
    Ok(listener)
}

/// accept4(SOCK_CLOEXEC), the call CPython's accept() makes; returns the fd and peer port.
#[cfg(target_os = "linux")]
fn accept(lfd: RawFd) -> io::Result<(RawFd, u16)> {
    let (mut peer, mut len) = (loopback(0), ADDR_LEN);
    let addr = (&mut peer as *mut libc::sockaddr_in).cast();
    let fd = check(unsafe { libc::accept4(lfd, addr, &mut len, libc::SOCK_CLOEXEC) })?;
    Ok((fd, u16::from_be(peer.sin_port)))
}

#[cfg(target_os = "linux")]
fn serve_blocking(lfd: RawFd, max_clients: usize) -> io::Result<()> {
    println!(
        "echo-blocking: pid {}, listening fd {lfd} on {}",
        std::process::id(),
        local_port(lfd)
    );
    let mut buf = vec![0u8; 65536];
    let mut served = 0;
    while max_clients == 0 || served < max_clients {
        let (fd, port) = accept(lfd)?; // blocks until the accept queue is non-empty
        let client = unsafe { OwnedFd::from_raw_fd(fd) }; // closed on drop, even if echoing fails
        println!("accept() = fd {fd} from port {port}");
        echo_blocking(fd, &mut buf)?;
        drop(client); // close()
        println!("close({fd})");
        served += 1;
    }
    Ok(())
}

/// Echo one client until it hangs up.
fn echo_blocking(fd: RawFd, buf: &mut [u8]) -> io::Result<()> {
    loop {
        let n = read(fd, buf)?; // blocks until bytes arrive or the peer closes
        println!("read({fd}) = {n}");
        if n == 0 {
            return Ok(());
        }
        let mut sent = 0;
        while sent < n {
            // write() may take fewer bytes than asked: send the rest.
            let written = write(fd, &buf[sent..n])?; // blocks while the send buffer is full
            println!("write({fd}) = {written}");
            sent += written;
        }
    }
}

/// One accepted client: its fd, closed when the Client is dropped, and the bytes
/// read but not yet written back (the loop owes them).
#[cfg(target_os = "linux")]
struct Client {
    _fd: OwnedFd,
    pending: Vec<u8>,
}

/// Set which readiness epoll reports for fd, level-triggered: EPOLLIN to read a
/// client, EPOLLOUT while we still owe it bytes. The u64 is the data the kernel
/// hands back with each event; storing the fd there says which one is ready.
#[cfg(target_os = "linux")]
fn interest(epfd: RawFd, op: libc::c_int, fd: RawFd, events: libc::c_int) -> io::Result<()> {
    let mut event = libc::epoll_event {
        events: events as u32,
        u64: fd as u64,
    };
    check(unsafe { libc::epoll_ctl(epfd, op, fd, &mut event) })?;
    Ok(())
}

#[cfg(target_os = "linux")]
fn serve_epoll(lfd: RawFd, max_clients: usize) -> io::Result<()> {
    let epoll = unsafe { OwnedFd::from_raw_fd(check(libc::epoll_create1(libc::EPOLL_CLOEXEC))?) };
    let epfd = epoll.as_raw_fd();
    interest(epfd, libc::EPOLL_CTL_ADD, lfd, libc::EPOLLIN)?;
    let pid = std::process::id();
    println!(
        "echo-epoll: pid {pid}, listening fd {lfd} on {}, epoll fd {epfd}",
        local_port(lfd)
    );
    // Every accepted fd lives in a Client, so returning (or an error) closes them all.
    let mut clients: HashMap<RawFd, Client> = HashMap::new();
    let mut events = [libc::epoll_event { events: 0, u64: 0 }; 64];
    let mut buf = vec![0u8; 65536];
    let mut served = 0;
    while max_clients == 0 || served < max_clients {
        // epoll_wait(): sleep until some fd is ready (-1: no timeout).
        let ret =
            unsafe { libc::epoll_wait(epfd, events.as_mut_ptr(), events.len() as libc::c_int, -1) };
        let n = match check(ret) {
            Ok(n) => n as usize,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue, // a signal, not readiness
            Err(e) => return Err(e),
        };
        // Copy the fds out: on x86-64 epoll_event is packed, so its fields cannot be borrowed.
        let ready: Vec<RawFd> = events[..n].iter().map(|event| event.u64 as RawFd).collect();
        let names: Vec<String> = ready.iter().map(|fd| format!("fd {fd}")).collect();
        println!("epoll_wait() = {n} ready: {}", names.join(", "));
        for fd in ready {
            if fd == lfd {
                accept_all(lfd, epfd, &mut clients)?;
                continue;
            }
            let Some(client) = clients.get_mut(&fd) else {
                continue;
            };
            // A client with pending output watches EPOLLOUT until we have written what we owe.
            let result = if client.pending.is_empty() {
                echo_until_eagain(fd, epfd, &mut buf, &mut client.pending)
            } else {
                flush_pending(fd, epfd, &mut client.pending)
            };
            let closed = match result {
                Ok(closed) => closed,
                Err(e) if matches!(e.raw_os_error(), Some(libc::ECONNRESET | libc::EPIPE)) => {
                    println!("fd {fd}: {}; closing", describe(&e));
                    true
                }
                Err(e) => return Err(e),
            };
            if closed {
                check(unsafe {
                    libc::epoll_ctl(epfd, libc::EPOLL_CTL_DEL, fd, std::ptr::null_mut())
                })?;
                clients.remove(&fd); // drops the OwnedFd: close()
                println!("close({fd})");
                served += 1;
            }
        }
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn accept_all(lfd: RawFd, epfd: RawFd, clients: &mut HashMap<RawFd, Client>) -> io::Result<()> {
    loop {
        let (fd, port) = match accept(lfd) {
            Ok(accepted) => accepted,
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                println!("accept() = EAGAIN (accept queue empty)");
                return Ok(());
            }
            Err(e) if e.raw_os_error() == Some(libc::EMFILE) => {
                // No fd left: the connection stays queued, the listener stays readable,
                // and level-triggered epoll would wake us again at once. Back off.
                println!("accept() = EMFILE (no free fd; the connection stays queued)");
                thread::sleep(Duration::from_secs(1));
                return Ok(());
            }
            Err(e) => return Err(e),
        };
        // Owned from here on: if a setup step fails, `?` drops it and the fd is closed.
        let owned = unsafe { OwnedFd::from_raw_fd(fd) };
        set_nonblocking(fd)?;
        interest(epfd, libc::EPOLL_CTL_ADD, fd, libc::EPOLLIN)?;
        let client = Client {
            _fd: owned,
            pending: Vec::new(),
        };
        clients.insert(fd, client);
        println!("accept() = fd {fd} from port {port}, O_NONBLOCK, added to epoll");
    }
}

/// Echo everything readable on fd; true when the peer has closed.
#[cfg(target_os = "linux")]
fn echo_until_eagain(
    fd: RawFd,
    epfd: RawFd,
    buf: &mut [u8],
    pending: &mut Vec<u8>,
) -> io::Result<bool> {
    loop {
        let n = match read(fd, buf) {
            Ok(n) => n,
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                println!("read({fd}) = EAGAIN (drained; back to epoll_wait)");
                return Ok(false);
            }
            Err(e) => return Err(e),
        };
        println!("read({fd}) = {n}");
        if n == 0 {
            return Ok(true);
        }
        if !write_or_keep(fd, epfd, &buf[..n], pending)? {
            return Ok(false); // the send buffer is full: stop reading until EPOLLOUT
        }
    }
}

/// Write data; keep what the send buffer refuses in `pending`. True if all of it went.
#[cfg(target_os = "linux")]
fn write_or_keep(fd: RawFd, epfd: RawFd, data: &[u8], pending: &mut Vec<u8>) -> io::Result<bool> {
    // write() may take only part of data, or nothing (EAGAIN).
    let sent = match write(fd, data) {
        Ok(n) => n,
        Err(e) if e.kind() == io::ErrorKind::WouldBlock => 0,
        Err(e) => return Err(e),
    };
    if sent == data.len() {
        println!("write({fd}) = {sent}");
        return Ok(true);
    }
    pending.extend_from_slice(&data[sent..]);
    // Watch EPOLLOUT instead of EPOLLIN: wake when the send buffer has room, and read
    // nothing more from this client until it has taken what we already owe it.
    interest(epfd, libc::EPOLL_CTL_MOD, fd, libc::EPOLLOUT)?;
    let result = if sent > 0 {
        format!("{sent} (short write")
    } else {
        "EAGAIN (send buffer full".to_string()
    };
    let owed = pending.len();
    println!("write({fd}) = {result}: {owed} bytes pending, waiting for EPOLLOUT)");
    Ok(false)
}

/// EPOLLOUT fired: write what we owe; once it is all gone, read the client again.
#[cfg(target_os = "linux")]
fn flush_pending(fd: RawFd, epfd: RawFd, pending: &mut Vec<u8>) -> io::Result<bool> {
    let owed = std::mem::take(pending);
    if write_or_keep(fd, epfd, &owed, pending)? {
        interest(epfd, libc::EPOLL_CTL_MOD, fd, libc::EPOLLIN)?;
        println!("epoll_ctl(MOD, fd {fd}, EPOLLIN): output drained, reading again");
    }
    Ok(false)
}

#[cfg(target_os = "linux")]
fn serve(mode: &str, lfd: RawFd, max_clients: usize) -> io::Result<()> {
    match mode {
        "blocking" => serve_blocking(lfd, max_clients),
        _ => serve_epoll(lfd, max_clients),
    }
}

/// Did `message` come back within `timeout`? The smoke clients use std::net:
/// they are the test harness, not the lesson.
fn wait_echo(client: &mut TcpStream, message: &[u8], timeout: Duration) -> bool {
    let mut buf = [0u8; 65536];
    if client.set_read_timeout(Some(timeout)).is_err() {
        return false;
    }
    matches!(client.read(&mut buf), Ok(n) if &buf[..n] == message)
}

fn echo_once(client: &mut TcpStream, message: &[u8], timeout: Duration) -> bool {
    client.write_all(message).is_ok() && wait_echo(client, message, timeout)
}

#[cfg(target_os = "linux")]
fn smoke_mode(mode: &'static str, port: u16) -> bool {
    let listener = match make_listener(port, mode == "epoll") {
        Ok(listener) => listener,
        Err(e) => {
            println!("echo: {}", describe(&e));
            return false;
        }
    };
    let lfd = listener.as_raw_fd();
    let (finished, done) = mpsc::channel();
    thread::spawn(move || {
        if let Err(e) = serve(mode, lfd, 2) {
            println!("echo: {}", describe(&e));
        }
        let _ = finished.send(());
    });
    let connect = || TcpStream::connect((Ipv4Addr::LOCALHOST, port));
    let (Ok(mut a), Ok(mut b)) = (connect(), connect()) else {
        println!("echo: smoke clients could not connect");
        return false;
    };
    let a_ok = echo_once(&mut a, b"hello from A\n", Duration::from_secs(1));
    let b_early = echo_once(&mut b, b"hello from B\n", Duration::from_millis(500)); // while A is still connected
    drop(a);
    let b_late = b_early || wait_echo(&mut b, b"hello from B\n", Duration::from_secs(1));
    drop(b);
    let _ = done.recv_timeout(Duration::from_secs(2)); // join the server, at most 2 s
    drop(listener);
    thread::sleep(Duration::from_millis(100));
    // Rust prints bools as true/false; the smoke lines keep Python's True/False.
    let shown = |ok: bool| if ok { "True" } else { "False" };
    if mode == "blocking" {
        let ok = a_ok && !b_early && b_late;
        println!(
            "smoke: blocking: B echoed only after A hung up: {}",
            shown(ok)
        );
        return ok;
    }
    let ok = a_ok && b_early;
    println!(
        "smoke: epoll: B echoed while A was still connected: {}",
        shown(ok)
    );
    ok
}

#[cfg(target_os = "linux")]
fn run(args: Args) -> ExitCode {
    if args.smoke {
        let results = [
            smoke_mode("blocking", args.port),
            smoke_mode("epoll", args.port),
        ];
        let ok = results.iter().all(|&passed| passed);
        println!("{}", if ok { "smoke: OK" } else { "smoke: FAIL" });
        return if ok {
            ExitCode::SUCCESS
        } else {
            ExitCode::FAILURE
        };
    }
    let served = make_listener(args.port, args.mode == "epoll")
        .and_then(|listener| serve(&args.mode, listener.as_raw_fd(), args.max_clients));
    match served {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            println!("echo: {}", describe(&e));
            ExitCode::FAILURE
        }
    }
}

#[cfg(not(target_os = "linux"))]
fn run(_args: Args) -> ExitCode {
    println!("echo: epoll is Linux-only; run it in the lab: just demo 00/05 rust");
    ExitCode::from(2)
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
    mode: String,
    port: u16,
    max_clients: usize,
    smoke: bool,
}

fn parse_args() -> Result<Args, String> {
    let mut parsed = Args {
        mode: "epoll".into(),
        port: 9005,
        max_clients: 0,
        smoke: false,
    };
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--mode" => parsed.mode = value(&mut args, &arg)?,
            "--port" => parsed.port = value(&mut args, &arg)?,
            "--max-clients" => parsed.max_clients = value(&mut args, &arg)?,
            "--smoke" => parsed.smoke = true,
            _ => return Err(format!("unexpected argument {arg}")),
        }
    }
    if parsed.mode != "blocking" && parsed.mode != "epoll" {
        return Err(format!(
            "--mode must be blocking or epoll, not {}",
            parsed.mode
        ));
    }
    Ok(parsed)
}

fn main() -> ExitCode {
    match parse_args() {
        Ok(args) => run(args),
        Err(msg) => {
            eprintln!("echo: {msg}");
            ExitCode::from(2)
        }
    }
}
