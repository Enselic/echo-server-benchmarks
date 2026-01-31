#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail -o xtrace

SSH_USER_AND_HOST=${1:-"martin@192.168.0.104"}

OUTPUT_DIR="$(pwd)/build"
mkdir -p $OUTPUT_DIR

PORT_BASE=7000

for server_binary in \
        go-tcp-echo-server \
        rust-tokio-tcp-echo-server \
        rust-threaded-tcp-echo-server \
    ; do

    (
        server_binary_path="$OUTPUT_DIR/$server_binary"

        cd $server_binary

        # Build server binary
        ./build.sh $server_binary_path

        # Kill old server if running
        ssh $SSH_USER_AND_HOST pkill -f $server_binary || echo "No existing $server_binary process"

        # Upload server binary
        scp $server_binary_path $SSH_USER_AND_HOST:/tmp/$server_binary

        # Use a unique port
        SERVER_PORT=$((PORT_BASE++))

        # Start server in background
        ssh $SSH_USER_AND_HOST "/tmp/$server_binary ${SERVER_PORT}" &
    )
done
