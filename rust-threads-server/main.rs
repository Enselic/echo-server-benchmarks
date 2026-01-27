use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;

fn main() -> std::io::Result<()> {
    let listener = TcpListener::bind("0.0.0.0:9001")?;
    println!("TCP echo server listening on :9001");

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
