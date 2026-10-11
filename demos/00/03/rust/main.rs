//! Lesson 0.3 demo (Rust): slowreader, a fast sender and a slow reader with a tiny receive buffer.
//!
//! The sender thread writes as fast as `write()` lets it. The reader asks for a
//! tiny SO_RCVBUF *before* connect() (the window scale is fixed in the SYN).
//! std's `TcpStream::connect` does socket() and connect() in one call and has
//! no buffer setter, so the reader socket is built with libc and then handed
//! to std. TCP flow control does the rest: the reader's buffer fills, it
//! advertises a zero window, the sender's buffer fills behind it, and write()
//! blocks. Nothing is lost; the flow just stops.
//!
//!     cargo run --release                          # 4 KiB buffer, 1 KiB every 100 ms, 10 s
//!     cargo run --release -- --rcvbuf 65536 --read-size 65536 --interval 0
//!     cargo run --release -- --rcvbuf 0 --read-size 65536 --interval 0
//!     cargo run --release -- --smoke               # 3 s, asserts that write() blocked

use std::io::{self, Read, Write};
use std::mem;
use std::net::{Ipv4Addr, TcpListener, TcpStream};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::process::ExitCode;
use std::sync::atomic::{AtomicU64, Ordering::Relaxed};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

static CHUNK: [u8; 65536] = [b'x'; 65536]; // the sender offers 64 KiB per write() call

/// Counters the sender thread updates and the reader loop reads.
struct Sender {
    epoch: Instant,           // the zero point for send_started
    sent: AtomicU64,          // bytes the kernel accepted into the send buffer
    send_started: AtomicU64,  // ns since epoch when the current write() began; 0 if none is
    longest_block: AtomicU64, // the longest write() call so far, in ns
}

impl Sender {
    /// How long the current write() call has been waiting (0 if none is).
    fn blocked_for(&self) -> Duration {
        match self.send_started.load(Relaxed) {
            0 => Duration::ZERO,
            started => self
                .epoch
                .elapsed()
                .saturating_sub(Duration::from_nanos(started)),
        }
    }

    fn note_block(&self, block: Duration) {
        self.longest_block
            .fetch_max(block.as_nanos() as u64, Relaxed);
    }

    fn run(&self, listener: TcpListener) {
        let Ok((mut conn, _)) = listener.accept() else {
            return;
        };
        loop {
            let now = self.epoch.elapsed().as_nanos().max(1) as u64;
            self.send_started.store(now, Relaxed);
            let result = conn.write(&CHUNK); // blocks while the send buffer is full
            self.note_block(self.blocked_for());
            self.send_started.store(0, Relaxed);
            match result {
                Ok(accepted) => self.sent.fetch_add(accepted as u64, Relaxed),
                Err(_) => return, // the reader closed: EPIPE or ECONNRESET
            };
        }
    }
}

/// libc calls return -1 and set errno on failure; turn that into an io::Error.
fn check(ret: libc::c_int) -> io::Result<libc::c_int> {
    if ret < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(ret)
}

fn rcvbuf_of(fd: &OwnedFd) -> io::Result<libc::c_int> {
    let (mut value, mut len) = (
        0 as libc::c_int,
        mem::size_of::<libc::c_int>() as libc::socklen_t,
    );
    let out = (&mut value as *mut libc::c_int).cast();
    check(unsafe {
        libc::getsockopt(
            fd.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_RCVBUF,
            out,
            &mut len,
        )
    })?;
    Ok(value)
}

fn connect_reader(port: u16, rcvbuf: libc::c_int) -> io::Result<TcpStream> {
    let fd = check(unsafe { libc::socket(libc::AF_INET, libc::SOCK_STREAM, 0) })?;
    let sock = unsafe { OwnedFd::from_raw_fd(fd) }; // closed on drop if anything below fails
    if rcvbuf > 0 {
        // Before connect(): the SYN carries the window scale chosen from this buffer,
        // and setting it also turns off receive-buffer autotuning for this socket.
        let opt = (&rcvbuf as *const libc::c_int).cast();
        let len = mem::size_of::<libc::c_int>() as libc::socklen_t;
        check(unsafe { libc::setsockopt(fd, libc::SOL_SOCKET, libc::SO_RCVBUF, opt, len) })?;
        let granted = rcvbuf_of(&sock)?;
        println!("slowreader: reader SO_RCVBUF asked {rcvbuf}, kernel set {granted}");
    } else {
        let granted = rcvbuf_of(&sock)?;
        println!("slowreader: reader SO_RCVBUF left to autotuning, starts at {granted}");
    }
    let mut addr: libc::sockaddr_in = unsafe { mem::zeroed() };
    addr.sin_family = libc::AF_INET as libc::sa_family_t;
    addr.sin_port = port.to_be(); // network byte order
    addr.sin_addr.s_addr = u32::from(Ipv4Addr::LOCALHOST).to_be();
    let len = mem::size_of::<libc::sockaddr_in>() as libc::socklen_t;
    check(unsafe { libc::connect(fd, (&addr as *const libc::sockaddr_in).cast(), len) })?;
    Ok(TcpStream::from(sock)) // from here on it is an ordinary blocking std socket
}

fn run(
    port: u16,
    rcvbuf: i32,
    read_size: usize,
    interval: f64,
    seconds: f64,
) -> io::Result<Arc<Sender>> {
    // std sets SO_REUSEADDR on Unix listeners. Its backlog is 128 rather than
    // Python's 1, which changes nothing for one connection (lesson 0.4 is about backlogs).
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, port))?;
    println!("slowreader: sender listening on 127.0.0.1:{port}");
    let sender = Arc::new(Sender {
        epoch: Instant::now(),
        sent: AtomicU64::new(0),
        send_started: AtomicU64::new(0),
        longest_block: AtomicU64::new(0),
    });
    let background = Arc::clone(&sender);
    thread::spawn(move || background.run(listener));

    let mut reader = connect_reader(port, rcvbuf)?;
    // f64's Display prints 5 and 2.5, like Python's {seconds:g}.
    println!("slowreader: reading {read_size} bytes every {interval:.3} s for {seconds} s");
    let mut buf = vec![0u8; read_size];
    let (mut read_total, started, mut next_report) = (0u64, Instant::now(), 1.0);
    loop {
        let elapsed = started.elapsed().as_secs_f64();
        if elapsed >= seconds {
            break;
        }
        read_total += reader.read(&mut buf)? as u64;
        if elapsed >= next_report {
            let sent = sender.sent.load(Relaxed);
            // An estimate of the bytes still in kernel buffers: completed send() calls
            // minus bytes read (ss's Send-Q + Recv-Q is the kernel's own, overlapping view).
            let in_kernel = sent as i64 - read_total as i64;
            let rate = read_total as f64 / elapsed / 1024.0;
            let blocked = sender.blocked_for().as_secs_f64() * 1000.0;
            println!(
                "t={next_report:.0}s sent={sent} read={read_total} in-kernel={in_kernel} \
                 read-rate={rate:.1} KiB/s send-blocked={blocked:.0}ms"
            );
            next_report += 1.0;
        }
        if interval > 0.0 {
            thread::sleep(Duration::from_secs_f64(interval));
        }
    }
    sender.note_block(sender.blocked_for());
    drop(reader);
    let longest = Duration::from_nanos(sender.longest_block.load(Relaxed)).as_secs_f64() * 1000.0;
    println!(
        "summary: sent={} read={read_total} longest send() block={longest:.0} ms",
        sender.sent.load(Relaxed)
    );
    Ok(sender)
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
    rcvbuf: i32,
    read_size: usize,
    interval: f64,
    seconds: f64,
    smoke: bool,
}

fn parse_args() -> Result<Args, String> {
    let mut parsed = Args {
        port: 9003,
        rcvbuf: 4096,
        read_size: 1024,
        interval: 0.1,
        seconds: 10.0,
        smoke: false,
    };
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--port" => parsed.port = value(&mut args, &arg)?,
            "--rcvbuf" => parsed.rcvbuf = value(&mut args, &arg)?,
            "--read-size" => parsed.read_size = value(&mut args, &arg)?,
            "--interval" => parsed.interval = value(&mut args, &arg)?,
            "--seconds" => parsed.seconds = value(&mut args, &arg)?,
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
            eprintln!("slowreader: {msg}");
            return ExitCode::from(2);
        }
    };
    let result = if args.smoke {
        run(args.port, 4096, 1024, 0.1, 3.0)
    } else {
        run(
            args.port,
            args.rcvbuf,
            args.read_size,
            args.interval,
            args.seconds,
        )
    };
    let sender = match result {
        Ok(sender) => sender,
        Err(e) => {
            println!("slowreader: {e}");
            return ExitCode::FAILURE;
        }
    };
    if !args.smoke {
        return ExitCode::SUCCESS;
    }
    if Duration::from_nanos(sender.longest_block.load(Relaxed)) >= Duration::from_millis(200) {
        println!("smoke: OK, the slow reader closed the window and send() blocked");
        return ExitCode::SUCCESS;
    }
    println!("smoke: FAIL, send() never blocked: flow control did not stop the sender");
    ExitCode::FAILURE
}
