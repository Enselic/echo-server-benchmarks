#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail -o xtrace

TEST_HOST=${1:-"192.168.0.104"}
TEST_USER=${2:-"martin"}
PARALLEL_CLIENTS=${3:-5000}

# todo explain
trap 'kill -- -$$' EXIT

SSH_USER_AND_HOST="${TEST_USER}@${TEST_HOST}"

# Don't let fd count limit us
ulimit -n $(cat /proc/sys/fs/nr_open)

OUTPUT_DIR="$(pwd)/build"
mkdir -p $OUTPUT_DIR

SERVER_PORT=7020

servers_to_test=(
    go-tcp-echo-server
    rust-tokio-tcp-echo-server
    rust-threaded-tcp-echo-server
)

for server_binary in "${servers_to_test[@]}"; do

    # Use a unique port
    SERVER_PORT=$((SERVER_PORT+1))

    (
        cd $server_binary

        server_binary_path="$OUTPUT_DIR/$server_binary"

        # Build server binary
        ./build.sh $server_binary_path

        # Kill old server if running
        ssh $SSH_USER_AND_HOST pkill -f $server_binary || echo "No existing $server_binary process"

        # Upload server binary
        scp $server_binary_path $SSH_USER_AND_HOST:/tmp/$server_binary

        # Start server in background
        echo "Starting $server_binary on port ${SERVER_PORT}..."
        ssh $SSH_USER_AND_HOST "ulimit -n 1048576 && /tmp/$server_binary ${SERVER_PORT}" &

        # Wait for server to start. Wait for port to be open
        echo "Waiting for $server_binary to start..."
        for i in {1..10}; do
            if nc -z $TEST_HOST $SERVER_PORT; then
                echo "$server_binary is up!"
                break
            else
                echo "Waiting for $server_binary to start... ($i)"
                sleep 1
            fi
        done
    
        # Run test
        timeout 10s go run ../go-client \
            --addr ${TEST_HOST}:${SERVER_PORT} \
            --num-parallel-clients ${PARALLEL_CLIENTS} \
            --num-total-requests 1000000000000 \
            || true

        # Rest
        echo Resting before next server test...
        sleep 5
    )
done
