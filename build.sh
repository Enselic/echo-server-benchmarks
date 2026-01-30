#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail -o xtrace

REMOTE_ADDR=${1:-"martin@192.168.0.104"}
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

        ssh $REMOTE_ADDR pkill $server
        "./$server/build.sh"
        scp build/$server $REMOTE_ADDR:/tmp/$server
    )

        

    # Build and deploy Rust tokio version
    cargo build --manifest-path rust-tokio-server/Cargo.toml --release
    cp rust-tokio-server/target/release/rust-tcp-echo-server build/
    scp build/rust-tcp-echo-server $REMOTE_ADDR:/tmp/rust-tcp-echo-server

    # Build and deploy Rust threads version
    rustc rust-threads-server/main.rs -o build/rust-threads-tcp-echo-server
    scp build/rust-threads-tcp-echo-server $REMOTE_ADDR:/tmp/rust-threads-tcp-echo-server
    # Run all three servers on the remote machine
    ssh $REMOTE_ADDR "/tmp/rust-tcp-echo-server ${TOKIO_PORT}" &
    ssh $REMOTE_ADDR "/tmp/rust-threads-tcp-echo-server ${THREADS_PORT}" &
    ssh $REMOTE_ADDR "/tmp/go-tcp-echo-server ${GO_PORT}"
    