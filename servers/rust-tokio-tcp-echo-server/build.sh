#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

output_path="$1"

cargo build --release
cp target/release/rust-tokio-tcp-echo-server "$output_path"
