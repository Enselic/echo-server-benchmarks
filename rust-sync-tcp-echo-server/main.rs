use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;

fn main() -> std::io::Result<()> {
    let port = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: rust-threads-tcp-echo-server <port>");
        std::process::exit(2);
    });

    let bind_addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&bind_addr)?;
    println!("Rust threaded TCP echo server listening on {}", bind_addr);

    for stream_result in listener.incoming() {
        let mut stream = match stream_result {
            Ok(stream) => stream,
            Err(_) => continue,
        };

        thread::spawn(move || {
            let mut buf = vec![0u8; 32 * 1024]; // 32 KB buffer
            loop {
                let n = match stream.read(&mut buf) {
                    Ok(0) => return, // connection closed
                    Ok(n) => n,
                    Err(_) => return,
                };

                if stream.write_all(&buf[..n]).is_err() {
                    return;
                }
            }
        });
    }

    Ok(())
}
