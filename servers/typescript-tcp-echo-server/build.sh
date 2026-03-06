#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="$1"
TEMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TEMP_DIR"' EXIT

tsc --target ES2020 --module commonjs --outDir "$TEMP_DIR" "$SCRIPT_DIR/main.ts"

{
    echo '#!/usr/bin/env node'
    cat "$TEMP_DIR/main.js"
} > "$OUTPUT_PATH"

chmod +x "$OUTPUT_PATH"
