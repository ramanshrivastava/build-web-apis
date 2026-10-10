//! Lesson 0.6 demo (Rust): the echo server on tokio, one task per connection.
//!
//! No epoll in sight, yet `stream.read().await` is a non-blocking read(2)
//! underneath: on EAGAIN the task returns Poll::Pending and the tokio I/O driver
//! (tokio/src/runtime/io/driver.rs, on top of mio's epoll selector) wakes it
//! when epoll says the fd is readable.
//!
//!     cargo run --release -- --smoke    # 50 concurrent clients, self-checking
//!
//! Minimal version written by the Author so lesson 0.6 can strace it; the
//! Porter refines it against PORT-SPEC.md.

use std::process::ExitCode;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const SMOKE_CLIENTS: usize = 50;

async fn handle(mut stream: TcpStream, quiet: bool, buf_size: usize) {
    let port = stream.peer_addr().map(|a| a.port()).unwrap_or(0);
    let mut buf = vec![0u8; buf_size];
    let mut echoed = 0usize;
    loop {
        // Pending until the I/O driver sees the fd readable, then read(2) runs.
        let n = match stream.read(&mut buf).await {
            Ok(0) | Err(_) => break, // 0: the peer closed
            Ok(n) => n,
        };
        if stream.write_all(&buf[..n]).await.is_err() {
            return;
        }
        echoed += n;
    }
    if !quiet {
        println!("port {port}: echoed {echoed} bytes, closed");
    }
}

async fn listen(port: u16) -> std::io::Result<TcpListener> {
    let listener = TcpListener::bind(("127.0.0.1", port)).await?;
    let workers = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1);
    println!(
        "echo-tokio: pid {}, listening on 127.0.0.1:{port} (multi-thread runtime, {workers} workers)",
        std::process::id()
    );
    Ok(listener)
}

async fn serve(listener: TcpListener, quiet: bool, buf_size: usize) {
    while let Ok((stream, _)) = listener.accept().await {
        tokio::spawn(handle(stream, quiet, buf_size));
    }
}

async fn one_client(port: u16, number: usize) -> bool {
    let Ok(mut stream) = TcpStream::connect(("127.0.0.1", port)).await else {
        return false;
    };
    let message = format!("hello from client {number}\n").into_bytes();
    if stream.write_all(&message).await.is_err() {
        return false;
    }
    let mut echoed = vec![0u8; message.len()];
    stream.read_exact(&mut echoed).await.is_ok() && echoed == message
}

async fn smoke(port: u16) -> ExitCode {
    let listener = match listen(port).await {
        Ok(l) => l,
        Err(e) => {
            println!("echo-tokio: {e}");
            return ExitCode::FAILURE;
        }
    };
    tokio::spawn(serve(listener, true, 65536));
    let clients: Vec<_> = (0..SMOKE_CLIENTS)
        .map(|n| tokio::spawn(one_client(port, n)))
        .collect();
    let mut ok = 0;
    for client in clients {
        if client.await.unwrap_or(false) {
            ok += 1;
        }
    }
    let workers = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1);
    if ok == SMOKE_CLIENTS {
        println!("smoke: OK, {ok} concurrent clients echoed by {workers} worker threads");
        ExitCode::SUCCESS
    } else {
        println!("smoke: FAIL, {ok} of {SMOKE_CLIENTS} clients got their echo");
        ExitCode::FAILURE
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut port: u16 = 9006;
    let mut buf_size: usize = 65536;
    let mut smoke_mode = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--smoke" => smoke_mode = true,
            "--port" => {
                i += 1;
                port = args.get(i).and_then(|p| p.parse().ok()).unwrap_or(port);
            }
            "--buf-size" => {
                i += 1;
                buf_size = args.get(i).and_then(|b| b.parse().ok()).unwrap_or(buf_size);
            }
            other => {
                println!("echo-tokio: unknown argument {other}");
                return ExitCode::from(2);
            }
        }
        i += 1;
    }
    if smoke_mode {
        return smoke(port).await;
    }
    match listen(port).await {
        Ok(listener) => {
            serve(listener, false, buf_size).await;
            ExitCode::SUCCESS
        }
        Err(e) => {
            println!("echo-tokio: {e}");
            ExitCode::FAILURE
        }
    }
}
