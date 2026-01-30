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
        rust-threaded-tcp-echo-server \
    ; do

    (
        cd $server

        ./build.sh $OUTPUT_DIR/$server


        ssh martin@192.168.0.104 pkill $server
        "./$server/build.sh"
        scp build/$server martin@192.168.0.104:/tmp/$server
    )

        

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
