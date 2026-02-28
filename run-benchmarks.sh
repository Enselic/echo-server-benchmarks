#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

PARALLEL_CLIENTS_VALUES="100 700 1500"

PAYLOAD_REPEAT_COUNT_VALUES="10 100 1000"

PAYLOADS_PER_CLIENT="2000"

REMOTE_PORT=9090

# First deploy servers
# if [ "$REMOTE_HOST" = "" ] || [ "$REMOTE_USER" = "" ]; then
#     echo "Error: REMOTE_HOST and REMOTE_USER environment variables must be set for deployment"
#     exit 1
# fi
# ./servers/deploy.sh

# We need many fds, so increase to max.
ulimit -n $(cat /proc/sys/fs/nr_open)

for PARALLEL_CLIENTS in $PARALLEL_CLIENTS_VALUES; do
    for PAYLOAD_REPEAT_COUNT in $PAYLOAD_REPEAT_COUNT_VALUES; do
        for SERVER in ./servers/*-tcp-echo-server; do
            SERVER_NAME=$(basename $SERVER)
            echo "Running ${SERVER_NAME} test with ${PARALLEL_CLIENTS} parallel clients, payload repeat count ${PAYLOAD_REPEAT_COUNT}, requests per client ${REQUESTS_PER_CLIENT}..."

            # HERE


            # To make each test run take approximately the same time, we keep the
            # total number of payloads sent by each client throughout the test
            # constant.
            REQUESTS_PER_CLIENT=$((PAYLOADS_PER_CLIENT / PAYLOAD_REPEAT_COUNT))
            # TODO: build from source
            tcp-echo-server-test-client \
                --addr "$REMOTE_HOST:${REMOTE_PORT}" \
                --parallel-clients ${PARALLEL_CLIENTS} \
                --requests-per-client ${REQUESTS_PER_CLIENT} \
                --payload-repeat-count ${PAYLOAD_REPEAT_COUNT}
        done
    done
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"


for i in "${!servers_to_test[@]}"; do
    server_binary="${servers_to_test[$i]}"
    SERVER_PORT=$(server_port_for_index $i)

    echo "Testing $server_binary on port ${SERVER_PORT}..."

    (
        cd "$SCRIPT_DIR/go-client"

        go run . "$@"
    )

    # Rest before next server test
    echo "Resting before next server test..."
    sleep 5
done

echo "All tests completed successfully!"
