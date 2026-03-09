#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail -o xtrace

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Don't let fd count limit us
ulimit -n $(cat /proc/sys/fs/nr_open)

cd "$SCRIPT_DIR"
cargo run --release -- "$@"
