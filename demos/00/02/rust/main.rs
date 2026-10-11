//! Lesson 0.2 demo (Rust): a DNS query built by hand and sent over UDP (RFC 1035).
//!
//! std only, no resolver crate: the 12-byte header and the question are built
//! with `u16::to_be_bytes`, sent with one `send_to()`, and the answer is parsed
//! from the bytes `recv_from()` returns, name compression included. If the
//! server sets TC (truncated), the query is repeated over TCP with a 2-byte
//! length prefix (RFC 1035 section 4.2.2, RFC 7766): DNS is UDP until it isn't.
//!
//!     rustc --edition 2021 -O main.rs -o dns
//!     ./dns example.com                    # A record via the resolver in /etc/resolv.conf
//!     ./dns --type TXT google.com          # big answers set TC=1 and fall back to TCP
//!     ./dns --server 1.1.1.1 --tcp example.com
//!     ./dns --smoke                        # needs network; run.sh skips it with CI_OFFLINE=1

use std::collections::hash_map::RandomState;
use std::hash::{BuildHasher, Hasher};
use std::io::{self, Read, Write};
use std::net::{Ipv4Addr, Ipv6Addr, TcpStream, ToSocketAddrs, UdpSocket};
use std::process::ExitCode;
use std::time::Duration;

const HEADER_LEN: usize = 12; // id, flags, qdcount, ancount, nscount, arcount
const TYPES: [(&str, u16); 6] = [
    ("A", 1),
    ("NS", 2),
    ("CNAME", 5),
    ("SOA", 6),
    ("TXT", 16),
    ("AAAA", 28),
];
const CLASS_IN: u16 = 1;
const UDP_LIMIT: usize = 512; // RFC 1035 2.3.4: a UDP message without EDNS(0) is at most 512 bytes
const TIMEOUT: Duration = Duration::from_secs(3);
const SHORT: &str = "message ends early"; // where Python raises IndexError

struct Header {
    id: u16,
    qr: u16,
    tc: u16,
    rd: u16,
    ra: u16,
    rcode: u16,
    qd: u16,
    an: u16,
}

fn type_code(name: &str) -> Option<u16> {
    TYPES
        .iter()
        .find(|(n, _)| *n == name)
        .map(|&(_, code)| code)
}

fn type_name(code: u16) -> String {
    match TYPES.iter().find(|&&(_, c)| c == code) {
        Some((name, _)) => name.to_string(),
        None => code.to_string(),
    }
}

fn rcode_name(rcode: u16) -> String {
    let names = [
        "NOERROR", "FORMERR", "SERVFAIL", "NXDOMAIN", "NOTIMP", "REFUSED",
    ];
    match names.get(usize::from(rcode)) {
        Some(name) => name.to_string(),
        None => rcode.to_string(),
    }
}

/// A random 16-bit query id without a crate: std seeds every RandomState from
/// the OS's random source, so a hasher that has hashed nothing is fresh bits.
fn random_id() -> u16 {
    RandomState::new().build_hasher().finish() as u16
}

/// xxd-style lines: offset, 16 bytes in hex, then the printable ASCII.
fn hexdump(data: &[u8]) -> Vec<String> {
    let mut lines = Vec::new();
    for (row, chunk) in data.chunks(16).enumerate() {
        let hexes: Vec<String> = chunk.iter().map(|b| format!("{b:02x}")).collect();
        let text: String = chunk
            .iter()
            .map(|&b| {
                if (32..127).contains(&b) {
                    b as char
                } else {
                    '.'
                }
            })
            .collect();
        lines.push(format!(
            "  {:04x}  {:<47}  {text}",
            row * 16,
            hexes.join(" ")
        ));
    }
    lines
}

/// example.com -> 07 'example' 03 'com' 00: length-prefixed labels.
fn encode_name(name: &str) -> Vec<u8> {
    let mut out = Vec::new();
    // The root name "." has no labels: it is just the final 00.
    for label in name
        .trim_end_matches('.')
        .split('.')
        .filter(|l| !l.is_empty())
    {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out
}

fn build_query(id: u16, name: &str, qtype: u16) -> Vec<u8> {
    let flags: u16 = 0x0100; // QR=0 (query), OPCODE=0, RD=1: please recurse for me
    let mut query = Vec::new();
    for field in [id, flags, 1, 0, 0, 0] {
        query.extend_from_slice(&field.to_be_bytes()); // network byte order
    }
    query.extend(encode_name(name));
    query.extend_from_slice(&qtype.to_be_bytes());
    query.extend_from_slice(&CLASS_IN.to_be_bytes());
    query
}

fn u16_at(msg: &[u8], at: usize) -> Result<u16, String> {
    match msg.get(at..at + 2) {
        Some(b) => Ok(u16::from_be_bytes([b[0], b[1]])),
        None => Err(SHORT.into()),
    }
}

fn u32_at(msg: &[u8], at: usize) -> Result<u32, String> {
    match msg.get(at..at + 4) {
        Some(b) => Ok(u32::from_be_bytes([b[0], b[1], b[2], b[3]])),
        None => Err(SHORT.into()),
    }
}

/// Read a (possibly compressed) name at `offset`. Borrows the message, returns
/// an owned String plus the offset just after the name where it started.
fn decode_name(msg: &[u8], mut offset: usize) -> Result<(String, usize), String> {
    let (mut labels, mut end, mut jumps) = (Vec::new(), None, 0);
    loop {
        let length = usize::from(*msg.get(offset).ok_or(SHORT)?);
        if length & 0xc0 == 0xc0 {
            // A pointer: the rest of the name lives elsewhere. Bounding the jumps
            // is not about memory safety; a looping pointer is a logic bug in any language.
            let low = usize::from(*msg.get(offset + 1).ok_or(SHORT)?);
            end.get_or_insert(offset + 2);
            offset = ((length & 0x3f) << 8) | low;
            jumps += 1;
            if jumps > 20 {
                return Err("compression loop".into());
            }
            continue;
        }
        if length == 0 {
            let name = if labels.is_empty() {
                ".".to_string()
            } else {
                labels.join(".")
            };
            return Ok((name, end.unwrap_or(offset + 1)));
        }
        let label = msg.get(offset + 1..offset + 1 + length).ok_or(SHORT)?;
        labels.push(String::from_utf8_lossy(label).into_owned());
        offset += 1 + length;
    }
}

fn describe_rdata(msg: &[u8], rtype: u16, start: usize, rdlength: usize) -> Result<String, String> {
    let rdata = msg.get(start..start + rdlength).ok_or(SHORT)?;
    if let (1, Ok(octets)) = (rtype, <[u8; 4]>::try_from(rdata)) {
        return Ok(Ipv4Addr::from(octets).to_string());
    }
    if let (28, Ok(octets)) = (rtype, <[u8; 16]>::try_from(rdata)) {
        return Ok(Ipv6Addr::from(octets).to_string());
    }
    if rtype == 2 || rtype == 5 {
        return Ok(decode_name(msg, start)?.0);
    }
    if rtype == 16 {
        let (mut text, mut i) = (Vec::new(), 0);
        while i < rdata.len() {
            let len = usize::from(rdata[i]);
            let piece = &rdata[i + 1..(i + 1 + len).min(rdata.len())];
            text.push(String::from_utf8_lossy(piece).into_owned());
            i += 1 + len;
        }
        let joined = text.join(" ");
        let head: String = joined.chars().take(60).collect(); // characters, not bytes
        let more = if joined.chars().count() > 60 {
            "..."
        } else {
            ""
        };
        return Ok(format!("\"{head}\"{more}"));
    }
    Ok(format!("({rdlength} bytes)"))
}

fn parse_response(msg: &[u8]) -> Result<(Header, Vec<String>), String> {
    if msg.len() < HEADER_LEN {
        return Err(SHORT.into());
    }
    let flags = u16_at(msg, 2)?;
    let header = Header {
        id: u16_at(msg, 0)?,
        qr: flags >> 15,
        tc: (flags >> 9) & 1,
        rd: (flags >> 8) & 1,
        ra: (flags >> 7) & 1,
        rcode: flags & 0xf,
        qd: u16_at(msg, 4)?,
        an: u16_at(msg, 6)?,
    };
    let mut offset = HEADER_LEN;
    for _ in 0..header.qd {
        offset = decode_name(msg, offset)?.1 + 4; // skip the echoed question
    }
    let mut answers = Vec::new();
    for _ in 0..header.an {
        let (name, next) = decode_name(msg, offset)?;
        let rtype = u16_at(msg, next)?; // then class (2), ttl (4), rdlength (2)
        let ttl = u32_at(msg, next + 4)?;
        let rdlength = usize::from(u16_at(msg, next + 8)?);
        offset = next + 10;
        let value = describe_rdata(msg, rtype, offset, rdlength)?;
        answers.push(format!("{name} {} {value} ttl={ttl}", type_name(rtype)));
        offset += rdlength;
    }
    Ok((header, answers))
}

/// io::Error texts, phrased like the Python demo's for the common cases.
fn io_message(err: io::Error) -> String {
    match err.kind() {
        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut => "timed out".into(),
        io::ErrorKind::UnexpectedEof => "server closed before the full answer arrived".into(),
        _ => err.to_string(),
    }
}

fn ask_udp(server: &str, port: u16, query: &[u8]) -> io::Result<Vec<u8>> {
    let sock = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0))?;
    sock.set_read_timeout(Some(TIMEOUT))?;
    let sent = sock.send_to(query, (server, port))?; // one datagram, no connection
    println!("sendto() {sent} bytes -> {server}:{port} (UDP)");
    let mut reply = vec![0u8; 4096];
    let (n, peer) = sock.recv_from(&mut reply)?; // one whole datagram, or nothing
    println!("recvfrom() {n} bytes <- {}:{}", peer.ip(), peer.port());
    reply.truncate(n);
    Ok(reply)
}

fn ask_tcp(server: &str, port: u16, query: &[u8]) -> io::Result<Vec<u8>> {
    let addr = (server, port)
        .to_socket_addrs()?
        .next()
        .ok_or(io::ErrorKind::NotFound)?;
    let mut stream = TcpStream::connect_timeout(&addr, TIMEOUT)?;
    stream.set_read_timeout(Some(TIMEOUT))?;
    stream.set_write_timeout(Some(TIMEOUT))?;
    let mut framed = (query.len() as u16).to_be_bytes().to_vec(); // TCP is a stream: add a length
    framed.extend_from_slice(query);
    stream.write_all(&framed)?; // loops until every byte is sent, like sendall()
    println!(
        "send() {} bytes -> {server}:{port} (TCP, 2-byte length + query)",
        framed.len()
    );
    let mut prefix = [0u8; 2];
    stream.read_exact(&mut prefix)?;
    let mut reply = vec![0u8; usize::from(u16::from_be_bytes(prefix))];
    stream.read_exact(&mut reply)?; // as many reads as it takes
    let n = reply.len();
    println!(
        "recv() {} bytes <- {server}:{port} (length prefix says {n})",
        2 + n
    );
    Ok(reply)
}

fn system_resolver() -> Option<String> {
    let conf = std::fs::read_to_string("/etc/resolv.conf").ok()?;
    conf.lines().find_map(|line| {
        let parts: Vec<&str> = line.split_whitespace().collect();
        let ipv4 = parts.len() >= 2 && parts[0] == "nameserver" && !parts[1].contains(':');
        ipv4.then(|| parts[1].to_string())
    })
}

fn show(header: &Header, answers: &[String]) {
    println!(
        "header: id=0x{:04x} qr={} tc={} rd={} ra={} rcode={} questions={} answers={}",
        header.id,
        header.qr,
        header.tc,
        header.rd,
        header.ra,
        rcode_name(header.rcode),
        header.qd,
        header.an
    );
    for answer in answers {
        println!("answer: {answer}");
    }
}

fn resolve(
    name: &str,
    qtype: &str,
    server: &str,
    port: u16,
    force_tcp: bool,
) -> Result<(Header, Vec<String>), String> {
    let id = random_id();
    let query = build_query(id, name, type_code(qtype).unwrap_or(1));
    println!("query: {name} {qtype} id=0x{id:04x}, {} bytes", query.len());
    for line in hexdump(&query) {
        println!("{line}");
    }
    let ask = if force_tcp { ask_tcp } else { ask_udp };
    let (header, answers) = checked_reply(&ask(server, port, &query).map_err(io_message)?, id)?;
    if header.tc == 1 && !force_tcp {
        println!(
            "truncated: the answer did not fit in {UDP_LIMIT} bytes of UDP; retrying over TCP"
        );
        // The TCP answer gets the same id check as the UDP one.
        return checked_reply(&ask_tcp(server, port, &query).map_err(io_message)?, id);
    }
    Ok((header, answers))
}

/// Parse a reply, and refuse it unless its id says it answers our query.
fn checked_reply(reply: &[u8], id: u16) -> Result<(Header, Vec<String>), String> {
    let (header, answers) = parse_response(reply)?;
    if header.id != id {
        return Err(format!("reply id 0x{:04x} does not match query", header.id));
    }
    show(&header, &answers);
    Ok((header, answers))
}

/// The lookups themselves; any socket or parse error ends them as `dns: FAIL, ...`.
fn lookups(
    name: &str,
    qtype: &str,
    server: &str,
    port: u16,
    force_tcp: bool,
    smoke: bool,
) -> Result<ExitCode, String> {
    if !smoke {
        resolve(name, qtype, server, port, force_tcp)?;
        return Ok(ExitCode::SUCCESS);
    }
    let (udp_header, udp_answers) = resolve("example.com", "A", server, port, false)?;
    let (tcp_header, tcp_answers) = resolve("example.com", "A", server, port, true)?;
    let found = udp_answers
        .iter()
        .chain(&tcp_answers)
        .filter(|a| a.contains(" A "))
        .count();
    if udp_header.rcode == 0 && tcp_header.rcode == 0 && found > 0 {
        println!("smoke: OK, example.com resolved over UDP and TCP ({found} A records)");
        return Ok(ExitCode::SUCCESS);
    }
    println!("smoke: FAIL, no A record for example.com");
    Ok(ExitCode::FAILURE)
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
    name: String,
    qtype: String,
    server: Option<String>,
    port: u16,
    tcp: bool,
    smoke: bool,
}

/// The same command line as the Python demo: NAME may come before or after the flags.
fn parse_args() -> Result<Args, String> {
    let mut parsed = Args {
        name: "example.com".into(),
        qtype: "A".into(),
        server: None,
        port: 53,
        tcp: false,
        smoke: false,
    };
    let (mut args, mut named) = (std::env::args().skip(1), false);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--type" => parsed.qtype = value(&mut args, &arg)?,
            "--server" => parsed.server = Some(value(&mut args, &arg)?),
            "--port" => parsed.port = value(&mut args, &arg)?,
            "--tcp" => parsed.tcp = true,
            "--smoke" => parsed.smoke = true,
            _ if arg.starts_with('-') || named => return Err(format!("unexpected argument {arg}")),
            _ => (parsed.name, named) = (arg, true),
        }
    }
    if type_code(&parsed.qtype).is_none() {
        return Err(format!(
            "--type must be one of A, AAAA, CNAME, NS, SOA, TXT, not {}",
            parsed.qtype
        ));
    }
    Ok(parsed)
}

fn main() -> ExitCode {
    let args = match parse_args() {
        Ok(args) => args,
        Err(msg) => {
            eprintln!("dns: {msg}");
            return ExitCode::from(2);
        }
    };
    let Some(server) = args.server.or_else(system_resolver) else {
        println!("dns: no IPv4 nameserver in /etc/resolv.conf; pass --server IP");
        return ExitCode::from(2);
    };
    println!("dns: resolver {server}:{}", args.port);
    match lookups(
        &args.name,
        &args.qtype,
        &server,
        args.port,
        args.tcp,
        args.smoke,
    ) {
        Ok(code) => code,
        Err(e) => {
            println!("dns: FAIL, {e}");
            ExitCode::FAILURE
        }
    }
}
