use async_net::TcpListener;
use futures_lite::io::{AsyncReadExt, AsyncWriteExt};

fn main() -> std::io::Result<()> {
    smol::block_on(async_main())
}

async fn async_main() -> std::io::Result<()> {
    let port = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: rust-echo-server <port>");
        std::process::exit(2);
    });

    let bind_addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&bind_addr).await?;
    // println!("Rust async TCP echo server listening on {}", bind_addr);

    loop {
        let (mut socket, _addr) = listener.accept().await?;

        smol::spawn(async move {
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
        })
        .detach();
    }
}
