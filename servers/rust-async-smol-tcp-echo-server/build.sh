#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="$(pwd)/$1"

cd "$SCRIPT_DIR"
cargo build --release
cp "$SCRIPT_DIR/target/release/rust-smol-tcp-echo-server" "$OUTPUT_PATH"
