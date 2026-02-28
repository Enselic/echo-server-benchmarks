#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# First build and deploy all servers
for SERVER in ./servers/*; do
    if [ ! -d "$SERVER" ]; then
        continue
    fi

    SERVER_NAME=$(basename $SERVER)
    echo "Building and deploying $SERVER_NAME..."
    $SERVER/build.sh ./build/$SERVER_NAME
    scp $USER@$HOST:./build/$SERVER_NAME $USER@$HOST:~/bin/$SERVER_NAME
done
