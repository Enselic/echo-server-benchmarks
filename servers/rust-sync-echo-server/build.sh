#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="$1"

rustc -O "$SCRIPT_DIR/main.rs" -o "$OUTPUT_PATH"
