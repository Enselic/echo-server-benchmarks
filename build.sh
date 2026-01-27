#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

mkdir -p build

# Build and deploy Go version
go build -o build/go-tcp-echo-server go/main.go
scp build/go-tcp-echo-server martin@192.168.0.104:/tmp/go-tcp-echo-server

# Build and deploy Rust version
cargo build --manifest-path rust/Cargo.toml --release
cp rust/target/release/rust-tcp-echo-server build/
scp build/rust-tcp-echo-server martin@192.168.0.104:/tmp/rust-tcp-echo-server

# Run both servers on the remote machine
ssh martin@192.168.0.104 /tmp/rust-tcp-echo-server &
ssh martin@192.168.0.104 /tmp/go-tcp-echo-server
