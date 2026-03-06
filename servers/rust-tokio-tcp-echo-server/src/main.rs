use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let port = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: rust-tcp-echo-server <port>");
        std::process::exit(2);
    });

    let bind_addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&bind_addr).await?;
    // println!("Rust async TCP echo server listening on {}", bind_addr);

    loop {
        let (mut socket, _addr) = listener.accept().await?;

        tokio::spawn(async move {
            let mut buf = vec![0u8; 32 * 1024]; // 32 KB buffer

            loop {
                let n = match socket.read(&mut buf).await {
                    Ok(0) => return, // connection closed
                    Ok(n) => n,
                    Err(_) => return,
                };

                if socket.write_all(&buf[..n]).await.is_err() {
                    return;
                }
            }
        });
    }
}
