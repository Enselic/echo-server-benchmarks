#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

# First build and deploy all servers
for SERVER in ./servers/*; do
    if [ ! -d "$SERVER" ]; then
        continue
    fi
    SERVER_NAME=$(basename $SERVER)

    echo "Building and deploying $SERVER_NAME..."
    $SERVER/build.sh "$BUILD_DIR/$SERVER_NAME"
    scp "$BUILD_DIR/$SERVER_NAME" "$REMOTE_USER@$REMOTE_HOST:~/bin/$SERVER_NAME"
done
