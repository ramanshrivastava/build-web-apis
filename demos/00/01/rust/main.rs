//! Lesson 0.1 demo (Rust): an AF_PACKET sniffer that prints each frame's MACs and EtherType.
//!
//! The same program as python/main.py through the libc crate: socket(AF_PACKET,
//! SOCK_RAW, htons(ETH_P_ALL)), bind() with a sockaddr_ll, and recvfrom() into a
//! sockaddr_ll whose sll_pkttype says which way the frame went. std has no
//! AF_PACKET wrapper, so every call is `unsafe` and reports failure as -1 plus
//! errno. Linux only, and it needs CAP_NET_RAW (root in the lab).
//!
//!     cargo run --release                          # 10 frames on lo
//!     cargo run --release -- --iface eth0 -n 5     # 5 frames on the lab's eth0
//!     cargo run --release -- --smoke               # send a UDP datagram on lo, find its frames

// The decoders are portable; only the socket calls are Linux-only.
#![cfg_attr(not(target_os = "linux"), allow(dead_code, unused_imports))]

use std::collections::BTreeSet;
use std::ffi::{CStr, CString};
use std::io;
use std::mem;
use std::net::{Ipv4Addr, UdpSocket};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::process::ExitCode;
use std::time::{Duration, Instant};

const ETH_HEADER_LEN: usize = 14; // dst MAC, src MAC, EtherType
const SMOKE_PORT: u16 = 9001;
const SMOKE_PAYLOAD: &[u8] = b"m0 smoke";

fn ethertype_name(ethertype: u16) -> &'static str {
    match ethertype {
        0x0800 => "IPv4",
        0x0806 => "ARP",
        0x86dd => "IPv6",
        0x8100 => "802.1Q",
        _ => "?",
    }
}

/// sll_pkttype, include/uapi/linux/if_packet.h: who the frame was for.
fn pkttype_name(pkttype: u8) -> String {
    match pkttype {
        0 => "host".into(),
        1 => "broadcast".into(),
        2 => "multicast".into(),
        3 => "otherhost".into(),
        4 => "outgoing".into(),
        n => n.to_string(),
    }
}

fn ip_proto_name(proto: u8) -> String {
    match proto {
        1 => "ICMP".into(),
        6 => "TCP".into(),
        17 => "UDP".into(),
        n => format!("proto {n}"),
    }
}

fn mac(raw: &[u8]) -> String {
    let octets: Vec<String> = raw.iter().map(|b| format!("{b:02x}")).collect();
    octets.join(":")
}

/// A 16-bit field in network byte order (big-endian), as every header stores it.
fn be16(bytes: &[u8], at: usize) -> u16 {
    u16::from_be_bytes([bytes[at], bytes[at + 1]])
}

fn ipv4(b: &[u8]) -> Ipv4Addr {
    Ipv4Addr::new(b[0], b[1], b[2], b[3])
}

/// One-line IPv4 summary, plus the UDP/TCP destination port if there is one.
fn describe_ipv4(packet: &[u8]) -> (String, Option<u16>) {
    if packet.len() < 20 {
        return ("short IPv4 header".into(), None);
    }
    let ihl = usize::from(packet[0] & 0x0f) * 4; // header length in 32-bit words
    let proto = packet[9];
    let (src, dst) = (ipv4(&packet[12..16]), ipv4(&packet[16..20]));
    let name = ip_proto_name(proto);
    if (proto == 6 || proto == 17) && packet.len() >= ihl + 4 {
        let (sport, dport) = (be16(packet, ihl), be16(packet, ihl + 2));
        return (format!("{name} {src}:{sport} > {dst}:{dport}"), Some(dport));
    }
    (format!("{name} {src} > {dst}"), None)
}

/// Frame summary line, its EtherType, and the transport destination port (if any).
fn describe(frame: &[u8], pkttype: u8) -> (String, u16, Option<u16>) {
    let (dst, src) = (&frame[0..6], &frame[6..12]);
    let ethertype = be16(frame, 12);
    let mut line = format!(
        "{} > {} type 0x{ethertype:04x} {} len {} {}",
        mac(src),
        mac(dst),
        ethertype_name(ethertype),
        frame.len(),
        pkttype_name(pkttype)
    );
    let mut dport = None;
    if ethertype == 0x0800 {
        let (summary, port) = describe_ipv4(&frame[ETH_HEADER_LEN..]);
        line = format!("{line} | {summary}");
        dport = port;
    }
    (line, ethertype, dport)
}

/// The C library's text for an errno ("No such device"), without Rust's " (os error 19)".
fn strerror(err: &io::Error) -> String {
    let text = unsafe { CStr::from_ptr(libc::strerror(err.raw_os_error().unwrap_or(0))) };
    text.to_string_lossy().into_owned()
}

/// Open the tap and bind it to one interface; returns the socket and its ifindex.
#[cfg(target_os = "linux")]
fn open_sniffer(iface: &str) -> io::Result<(OwnedFd, u32)> {
    // SOCK_RAW keeps the link-layer header; htons(ETH_P_ALL) asks for every EtherType.
    let protocol = (libc::ETH_P_ALL as u16).to_be();
    let fd = unsafe { libc::socket(libc::AF_PACKET, libc::SOCK_RAW, protocol as i32) };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    let sock = unsafe { OwnedFd::from_raw_fd(fd) }; // closed on drop, on every path below
    let name = CString::new(iface).map_err(|_| io::Error::from_raw_os_error(libc::ENODEV))?;
    let ifindex = unsafe { libc::if_nametoindex(name.as_ptr()) };
    if ifindex == 0 {
        return Err(io::Error::last_os_error()); // ENODEV: no such interface
    }
    // One interface, not all of them. sll_protocol is in network byte order too.
    let mut addr: libc::sockaddr_ll = unsafe { mem::zeroed() };
    addr.sll_family = libc::AF_PACKET as u16;
    addr.sll_protocol = protocol;
    addr.sll_ifindex = ifindex as i32;
    let len = mem::size_of::<libc::sockaddr_ll>() as libc::socklen_t;
    let ret = unsafe { libc::bind(fd, (&addr as *const libc::sockaddr_ll).cast(), len) };
    if ret < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok((sock, ifindex))
}

/// One recvfrom(): the frame's length and the sll_pkttype of the sockaddr_ll beside it.
#[cfg(target_os = "linux")]
fn recv_frame(fd: RawFd, buf: &mut [u8]) -> io::Result<(usize, u8)> {
    let mut addr: libc::sockaddr_ll = unsafe { mem::zeroed() };
    let mut len = mem::size_of::<libc::sockaddr_ll>() as libc::socklen_t;
    let from = (&mut addr as *mut libc::sockaddr_ll).cast();
    let n = unsafe { libc::recvfrom(fd, buf.as_mut_ptr().cast(), buf.len(), 0, from, &mut len) };
    if n < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok((n as usize, addr.sll_pkttype))
}

/// SO_RCVTIMEO: recvfrom() gives up after `timeout`, so the deadline is honoured.
#[cfg(target_os = "linux")]
fn set_recv_timeout(fd: RawFd, timeout: Duration) -> io::Result<()> {
    let tv = libc::timeval {
        tv_sec: timeout.as_secs() as libc::time_t,
        tv_usec: timeout.subsec_micros() as libc::suseconds_t,
    };
    let len = mem::size_of::<libc::timeval>() as libc::socklen_t;
    let opt = (&tv as *const libc::timeval).cast();
    let ret = unsafe { libc::setsockopt(fd, libc::SOL_SOCKET, libc::SO_RCVTIMEO, opt, len) };
    if ret < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

/// Send three UDP datagrams to 127.0.0.1:9001 with a receiver bound, so no ICMP error.
fn send_smoke_datagrams() -> io::Result<UdpSocket> {
    let receiver = UdpSocket::bind((Ipv4Addr::LOCALHOST, SMOKE_PORT))?;
    let sender = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0))?;
    for _ in 0..3 {
        sender.send_to(SMOKE_PAYLOAD, (Ipv4Addr::LOCALHOST, SMOKE_PORT))?;
    }
    Ok(receiver)
}

#[cfg(target_os = "linux")]
fn sniff(iface: &str, count: usize, timeout: Duration, smoke: bool) -> ExitCode {
    let (sock, ifindex) = match open_sniffer(iface) {
        Ok(opened) => opened,
        Err(e) if matches!(e.raw_os_error(), Some(libc::EPERM | libc::EACCES)) => {
            println!("sniff: AF_PACKET needs CAP_NET_RAW; run as root (the lab runs as root)");
            return ExitCode::from(3);
        }
        Err(e) => {
            println!("sniff: cannot bind to '{iface}': {}", strerror(&e));
            return ExitCode::from(2);
        }
    };
    let fd = sock.as_raw_fd();
    println!("sniff: AF_PACKET socket fd={fd} bound to {iface} (ifindex {ifindex})");
    let _receiver = match smoke.then(send_smoke_datagrams).transpose() {
        Ok(receiver) => receiver, // kept open until we return, like Python's
        Err(e) => {
            println!("sniff: smoke datagrams: {e}");
            return ExitCode::FAILURE;
        }
    };
    if let Err(e) = set_recv_timeout(fd, Duration::from_millis(500)) {
        println!("sniff: SO_RCVTIMEO: {}", strerror(&e));
        return ExitCode::FAILURE;
    }
    let mut buf = vec![0u8; 65535];
    let deadline = Instant::now() + timeout;
    let (mut seen, mut matched) = (0, BTreeSet::new());
    while seen < count && Instant::now() < deadline {
        let (n, pkttype) = match recv_frame(fd, &mut buf) {
            Ok(frame) => frame,
            // EAGAIN: the 0.5 s timeout expired with no frame; check the deadline again.
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => continue,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => {
                println!("sniff: recvfrom: {}", strerror(&e));
                return ExitCode::FAILURE;
            }
        };
        if n < ETH_HEADER_LEN {
            continue;
        }
        seen += 1;
        let (line, ethertype, dport) = describe(&buf[..n], pkttype);
        println!("frame {seen}: {line}");
        if smoke && ethertype == 0x0800 && dport == Some(SMOKE_PORT) {
            matched.insert(pkttype_name(pkttype));
            if matched.contains("outgoing") && matched.contains("host") {
                break;
            }
        }
    }
    if !smoke {
        return ExitCode::SUCCESS;
    }
    if matched.contains("outgoing") && matched.contains("host") {
        println!("smoke: OK, the datagram to :{SMOKE_PORT} crossed {iface} twice (outgoing, host)");
        return ExitCode::SUCCESS;
    }
    let copies = if matched.is_empty() {
        "no".to_string()
    } else {
        format!("[{}]", Vec::from_iter(matched).join(" "))
    };
    println!("smoke: FAIL, saw {copies} copies of the datagram to :{SMOKE_PORT}");
    ExitCode::FAILURE
}

#[cfg(not(target_os = "linux"))]
fn sniff(_iface: &str, _count: usize, _timeout: Duration, _smoke: bool) -> ExitCode {
    println!("sniff: AF_PACKET is Linux-only; run it in the lab: just demo 00/01 rust");
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

fn main() -> ExitCode {
    let mut iface = String::from("lo");
    let mut count: usize = 10;
    let mut timeout: f64 = 10.0;
    let mut smoke = false;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        let parsed = match arg.as_str() {
            "--smoke" => {
                smoke = true;
                Ok(())
            }
            "--iface" => value(&mut args, &arg).map(|v| iface = v),
            "-n" | "--count" => value(&mut args, &arg).map(|v| count = v),
            "--timeout" => value(&mut args, &arg).map(|v| timeout = v),
            _ => Err(format!("unknown argument {arg}")),
        };
        if let Err(msg) = parsed {
            eprintln!("sniff: {msg}");
            return ExitCode::from(2);
        }
    }
    if smoke {
        return sniff("lo", 50, Duration::from_secs(5), true);
    }
    sniff(&iface, count, Duration::from_secs_f64(timeout), false)
}
