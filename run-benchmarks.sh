#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PARALLEL_CLIENTS_VALUES="100 700 1500"

PAYLOAD_REPEAT_COUNT_VALUES="10 100 1000"

PAYLOADS_PER_CLIENT="200000"

REMOTE_PORT=9092

# First deploy servers
# if [ "$REMOTE_HOST" = "" ] || [ "$REMOTE_USER" = "" ]; then
#     echo "Error: REMOTE_HOST and REMOTE_USER environment variables must be set for deployment"
#     exit 1
# fi
# ./servers/deploy.sh

# We need many fds, so increase to max.
ulimit -n $(cat /proc/sys/fs/nr_open)

# for SERVER in ./servers/*-tcp-echo-server; do
#     SERVER_NAME=$(basename $SERVER)
#     ssh "${REMOTE_USER}@${REMOTE_HOST}" "pkill --full ${SERVER_NAME}" 2>/dev/null || true
# done
# Build test client from source
echo "Building tcp-echo-server-test-client..."
(cd "$SCRIPT_DIR/test-client" && go build -o "$SCRIPT_DIR/build/tcp-echo-server-test-client" .)
PATH="$SCRIPT_DIR/build:$PATH"

iteration=1
for PARALLEL_CLIENTS in $PARALLEL_CLIENTS_VALUES; do
    for PAYLOAD_REPEAT_COUNT in $PAYLOAD_REPEAT_COUNT_VALUES; do
        for SERVER in "$SCRIPT_DIR"/servers/*-tcp-echo-server; do
            SERVER_NAME=$(basename $SERVER)
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "pkill --full ${SERVER_NAME}" 2>/dev/null || true

            # TODO: explain
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "echo $iteration > /tmp/iteration"

            # Start the server on the remote host
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "/home/martin/bin/${SERVER_NAME} ${REMOTE_PORT}" &
            trap 'ssh "${REMOTE_USER}@${REMOTE_HOST}" "pkill --full ${SERVER_NAME}" 2>/dev/null || true' EXIT

            # To make each test run take approximately the same time, we keep the
            # total number of payloads sent by each client throughout the test
            # constant.
            REQUESTS_PER_CLIENT=$((PAYLOADS_PER_CLIENT / PAYLOAD_REPEAT_COUNT))
            echo "${iteration}: Running ${SERVER_NAME} test with ${PARALLEL_CLIENTS} parallel clients, payload repeat count ${PAYLOAD_REPEAT_COUNT}, requests per client ${REQUESTS_PER_CLIENT}..."
            tcp-echo-server-test-client \
                --addr "$REMOTE_HOST:${REMOTE_PORT}" \
                --parallel-clients ${PARALLEL_CLIENTS} \
                --requests-per-client ${REQUESTS_PER_CLIENT} \
                --payload-repeat-count ${PAYLOAD_REPEAT_COUNT}

            # Stop the server
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "pkill --full ${SERVER_NAME}" 2>/dev/null || true
            trap - EXIT

            iteration=$((iteration + 1))
        done
    done
done

echo "All benchmarks completed successfully!"
