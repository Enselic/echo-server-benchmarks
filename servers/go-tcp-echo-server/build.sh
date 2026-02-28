#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

output_path="$1"

go build -o "$output_path" "$SCRIPT_DIR/main.go"
