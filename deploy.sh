#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail -o xtrace

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

mkdir -p "$OUTPUT_DIR"

for i in "${!servers_to_test[@]}"; do
    server_binary="${servers_to_test[$i]}"
    SERVER_PORT=$(server_port_for_index $i)

    (
        cd "$SCRIPT_DIR/$server_binary"

        server_binary_path="$OUTPUT_DIR/$server_binary"

        # Build server binary
        ./build.sh "$server_binary_path"

        # Kill old server if running
        ssh $SSH_USER_AND_HOST pkill -f "$server_binary" || echo "No existing $server_binary process"

        # Upload server binary
        ssh $SSH_USER_AND_HOST "mkdir -p $DEPLOY_DIR"
        scp "$server_binary_path" "$SSH_USER_AND_HOST:$DEPLOY_DIR/$server_binary"

        # Start server in background
        echo "Starting $server_binary on port ${SERVER_PORT}..."
        ssh $SSH_USER_AND_HOST "ulimit -n 1048576 && $DEPLOY_DIR/$server_binary ${SERVER_PORT}" &

        # Wait for server to start
        echo "Waiting for $server_binary to start..."
        for j in {1..10}; do
            if nc -z "$TEST_HOST" "$SERVER_PORT"; then
                echo "$server_binary is up!"
                break
            else
                echo "Waiting for $server_binary to start... ($j)"
                sleep 1
            fi
        done
    )
done

echo "All servers deployed and running!"
