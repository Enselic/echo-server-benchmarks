#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="$1"
TEMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TEMP_DIR"' EXIT

if command -v tsc >/dev/null 2>&1; then
    tsc --target ES2020 --module commonjs --outDir "$TEMP_DIR" "$SCRIPT_DIR/main.ts"
else
    npx --yes --package typescript tsc --target ES2020 --module commonjs --outDir "$TEMP_DIR" "$SCRIPT_DIR/main.ts"
fi

{
    echo '#!/usr/bin/env node'
    cat "$TEMP_DIR/main.js"
} > "$OUTPUT_PATH"

chmod +x "$OUTPUT_PATH"
