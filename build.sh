#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

mkdir -p build
go build -o build/go-tcp-echo-server go/main.go

cargo rustc --manifest-path rust/Cargo.toml --release -- -o build/rust-tcp-echo-server
