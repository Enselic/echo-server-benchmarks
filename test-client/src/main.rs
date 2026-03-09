use clap::Parser;
use std::error::Error;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::{sleep, timeout, Instant};

#[derive(Parser, Debug, Clone)]
#[command(name = "tcp-echo-server-test-client")]
struct CliArgs {
    #[arg(short = 'a', long = "addr", default_value = "localhost:80")]
    addr: String,

    #[arg(short = 'r', long = "requests-per-client", default_value_t = 1)]
    requests_per_client: u64,

    #[arg(short = 'p', long = "parallel-clients", default_value_t = 1)]
    parallel_clients: u64,

    #[arg(short = 'n', long = "payload-repeat-count", default_value_t = 1)]
    payload_repeat_count: u64,

    #[arg(short = 'd', long = "debug")]
    debug: bool,

    #[arg(long = "latency-ms-file")]
    latency_ms_file: Option<String>,
}

fn make_payload_unit(client_id: u64, seq: u64) -> [u8; 16] {
    let mut unit = [0_u8; 16];
    unit[..8].copy_from_slice(&client_id.to_be_bytes());
    unit[8..].copy_from_slice(&seq.to_be_bytes());
    unit
}

fn make_payload_bytes(unit: [u8; 16], repeat_count: u64) -> Vec<u8> {
    let mut buf = Vec::with_capacity(repeat_count as usize * 16);
    for _ in 0..repeat_count {
        buf.extend_from_slice(&unit);
    }
    buf
}

async fn do_request_on_conn(
    conn: &mut TcpStream,
    client_id: u64,
    seq: u64,
    payload_repeat_count: u64,
) -> Result<Duration, Box<dyn Error + Send + Sync>> {
    let unit = make_payload_unit(client_id, seq);
    let payload = make_payload_bytes(unit, payload_repeat_count);
    let mut reply = vec![0_u8; payload.len()];

    let start = Instant::now();

    timeout(Duration::from_secs(30), conn.write_all(&payload)).await??;
    timeout(Duration::from_secs(30), conn.read_exact(&mut reply)).await??;

    for i in 0..payload_repeat_count as usize {
        let off = i * 16;
        let got_client = u64::from_be_bytes(reply[off..off + 8].try_into()?);
        let got_seq = u64::from_be_bytes(reply[off + 8..off + 16].try_into()?);
        if got_client != client_id || got_seq != seq {
            return Err(format!(
                "client {} echo mismatch on {} (copy {}): want [{},{}] got [{},{}]",
                client_id, seq, i, client_id, seq, got_client, got_seq
            )
            .into());
        }
    }

    Ok(start.elapsed())
}

async fn wait_for_addr_with_timeout(
    addr: &str,
    total_timeout: Duration,
) -> Result<(), Box<dyn Error + Send + Sync>> {
    let started = Instant::now();

    loop {
        match timeout(Duration::from_secs(2), TcpStream::connect(addr)).await {
            Ok(Ok(conn)) => {
                drop(conn);
                return Ok(());
            }
            Ok(Err(_)) | Err(_) => {
                // Keep retrying until total timeout is reached.
            }
        }

        if started.elapsed() >= total_timeout {
            return Err(format!("timed out waiting for {}", addr).into());
        }

        sleep(Duration::from_millis(500)).await;
    }
}

#[tokio::main(flavor = "multi_thread")]
async fn main() {
    if let Err(err) = run().await {
        eprintln!("{}", err);
        std::process::exit(1);
    }
}

async fn run() -> Result<(), Box<dyn Error + Send + Sync>> {
    let args = CliArgs::parse();

    if args.payload_repeat_count == 0 {
        return Err("payload-repeat-count must be >= 1".into());
    }

    wait_for_addr_with_timeout(&args.addr, Duration::from_secs(20)).await?;

    let mut handles = Vec::with_capacity(args.parallel_clients as usize);
    for client_id in 0..args.parallel_clients {
        let local_args = args.clone();
        handles.push(tokio::spawn(async move {
            if local_args.debug {
                eprintln!("debug: dialing client={} addr={}", client_id, local_args.addr);
            }

            let mut conn = timeout(Duration::from_secs(120), TcpStream::connect(&local_args.addr))
                .await
                .map_err(|_| format!("client {} connect timed out", client_id))??;

            let mut local_latencies = Vec::with_capacity(local_args.requests_per_client as usize);
            for seq in 1..=local_args.requests_per_client {
                let latency = do_request_on_conn(
                    &mut conn,
                    client_id,
                    seq,
                    local_args.payload_repeat_count,
                )
                .await?;
                local_latencies.push(latency);
            }

            Ok::<Vec<Duration>, Box<dyn Error + Send + Sync>>(local_latencies)
        }));
    }

    let mut all_latencies =
        Vec::with_capacity((args.parallel_clients * args.requests_per_client) as usize);
    for handle in handles {
        let client_latencies = handle
            .await
            .map_err(|e| format!("client task panicked: {}", e))??;
        all_latencies.extend(client_latencies);
    }

    if all_latencies.is_empty() {
        return Err("no latencies recorded".into());
    }

    all_latencies.sort_unstable();

    if let Some(path) = &args.latency_ms_file {
        let file = File::create(path)?;
        let mut writer = BufWriter::new(file);
        for latency in &all_latencies {
            // One latency in milliseconds per line for downstream plotting.
            writeln!(writer, "{:.6}", latency.as_secs_f64() * 1_000.0)?;
        }
        writer.flush()?;
    }

    Ok(())
}
