#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

mkdir -p build

# Build and deploy Go version
go build -o build/go-tcp-echo-server go/main.go
scp build/go-tcp-echo-server martin@192.168.0.104:/tmp/go-tcp-echo-server

# Build and deploy Rust tokio version
cargo build --manifest-path rust-tokio-server/Cargo.toml --release
cp rust-tokio-server/target/release/rust-tcp-echo-server build/
scp build/rust-tcp-echo-server martin@192.168.0.104:/tmp/rust-tcp-echo-server

# Build and deploy Rust threads version
rustc rust-threads-server/main.rs -o build/rust-threads-tcp-echo-server
scp build/rust-threads-tcp-echo-server martin@192.168.0.104:/tmp/rust-threads-tcp-echo-server

# Run all three servers on the remote machine
ssh martin@192.168.0.104 /tmp/rust-tcp-echo-server &
ssh martin@192.168.0.104 /tmp/rust-threads-tcp-echo-server &
ssh martin@192.168.0.104 /tmp/go-tcp-echo-server
