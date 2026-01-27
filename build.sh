#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

mkdir -p build
go build -o build/go-tcp-echo-server go/main.go

cargo build --manifest-path rust/Cargo.toml --release
cp rust/target/release/rust-tcp-echo-server build/
