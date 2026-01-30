#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail -o xtrace

TOKIO_PORT="${TOKIO_PORT:-9001}"
GO_PORT="${GO_PORT:-9002}"
THREADS_PORT="${THREADS_PORT:-9003}"

OUTPUT_DIR="$(pwd)/build"
mkdir -p $OUTPUT_DIR

for server in \
        go-tcp-echo-server \
        rust-tokio-tcp-echo-server \
        rust-threads-tcp-echo-server \
    ; do

    case $server in
        go-tcp-echo-server)
            build_cmd="go build -o $OUTPUT_DIR/$server go-server/main.go"
            ;;
        rust-tokio-tcp-echo-server)
            build_cmd="cargo build --manifest-path rust-tokio-server/Cargo.toml --release && cp rust-tokio-server/target/release/rust-tcp-echo-server build/$server"
            ;;
        rust-threads-tcp-echo-server)
            build_cmd="rustc rust-threads-server/main.rs -o build/$server"
            ;;
        *)
            echo "Unknown server: $server"
            exit 1
            ;;
    esac

    ssh martin@192.168.0.104 pkill $server
    "./$server/build.sh"
    scp build/$server martin@192.168.0.104:/tmp/$server

    if ssh martin@

# Build and deploy Go version
go build -o build/go-tcp-echo-server go-server/main.go

# Build and deploy Rust tokio version
cargo build --manifest-path rust-tokio-server/Cargo.toml --release
cp rust-tokio-server/target/release/rust-tcp-echo-server build/
scp build/rust-tcp-echo-server martin@192.168.0.104:/tmp/rust-tcp-echo-server

# Build and deploy Rust threads version
rustc rust-threads-server/main.rs -o build/rust-threads-tcp-echo-server
scp build/rust-threads-tcp-echo-server martin@192.168.0.104:/tmp/rust-threads-tcp-echo-server

# Run all three servers on the remote machine
ssh martin@192.168.0.104 "/tmp/rust-tcp-echo-server ${TOKIO_PORT}" &
ssh martin@192.168.0.104 "/tmp/rust-threads-tcp-echo-server ${THREADS_PORT}" &
ssh martin@192.168.0.104 "/tmp/go-tcp-echo-server ${GO_PORT}"
