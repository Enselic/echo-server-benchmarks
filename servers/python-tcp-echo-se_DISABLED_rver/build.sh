#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="$1"

cp "$SCRIPT_DIR/main.py" "$OUTPUT_PATH"
chmod +x "$OUTPUT_PATH"
