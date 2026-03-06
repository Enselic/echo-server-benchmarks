#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="$1"
TEMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/classes"
javac --release 17 -d "$TEMP_DIR/classes" "$SCRIPT_DIR/src/Main.java"

echo 'Main-Class: Main' > "$TEMP_DIR/MANIFEST.MF"
jar --create --file "$TEMP_DIR/server.jar" --manifest "$TEMP_DIR/MANIFEST.MF" -C "$TEMP_DIR/classes" .

cat > "$OUTPUT_PATH" <<'EOF'
#!/usr/bin/env sh
exec java -jar "$0" "$@"
EOF
printf '\n' >> "$OUTPUT_PATH"
cat "$TEMP_DIR/server.jar" >> "$OUTPUT_PATH"

chmod +x "$OUTPUT_PATH"
