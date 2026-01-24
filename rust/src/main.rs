use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let listener = TcpListener::bind("0.0.0.0:9001").await?;
    println!("TCP echo server listening on :9001");

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
