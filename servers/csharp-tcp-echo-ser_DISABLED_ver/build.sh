#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="$1"
PUBLISH_DIR="$(mktemp -d)"

trap 'rm -rf "$PUBLISH_DIR"' EXIT

dotnet publish "$SCRIPT_DIR/csharp-echo-server.csproj" \
    --configuration Release \
    --runtime linux-x64 \
    -p:PublishSingleFile=true \
    -p:SelfContained=true \
    --output "$PUBLISH_DIR"

cp "$PUBLISH_DIR/csharp-echo-server" "$OUTPUT_PATH"
chmod +x "$OUTPUT_PATH"
