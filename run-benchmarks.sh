#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PARALLEL_CLIENTS_VALUES="700"
#PARALLEL_CLIENTS_VALUES="100 700 1500"

# Format per entry: <requests-per-client>:<payload-repeat-count>
REQUESTS_PER_CLIENT_AND_PAYLOAD_REPEAT_COUNT_PAIRS="5000:10"
#REQUESTS_PER_CLIENT_AND_PAYLOAD_REPEAT_COUNT_PAIRS="2000:10 200:100 20:1000"

REMOTE_PORT=9092
RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
MONITOR_OUTPUT_DIR="/tmp/echo-server-benchmarks-${RUN_TIMESTAMP}"

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
(cd "$SCRIPT_DIR/test-client" && cargo build --release)
cp "$SCRIPT_DIR/test-client/target/release/tcp-echo-server-test-client" "$SCRIPT_DIR/build/tcp-echo-server-test-client"
PATH="$SCRIPT_DIR/build:$PATH"
mkdir -p "${MONITOR_OUTPUT_DIR}"

for PARALLEL_CLIENTS in $PARALLEL_CLIENTS_VALUES; do
    for REQUEST_PAYLOAD_PAIR in $REQUESTS_PER_CLIENT_AND_PAYLOAD_REPEAT_COUNT_PAIRS; do
        IFS=':' read -r REQUESTS_PER_CLIENT PAYLOAD_REPEAT_COUNT <<<"$REQUEST_PAYLOAD_PAIR"

        for SERVER in "$SCRIPT_DIR"/servers/*-tcp-echo-server; do
            SERVER_NAME=$(basename $SERVER)
            TSV_FILE="${MONITOR_OUTPUT_DIR}/${SERVER_NAME}.tsv"
            PNG_FILE="${MONITOR_OUTPUT_DIR}/${SERVER_NAME}.png"
            LATENCY_MS_FILE="${MONITOR_OUTPUT_DIR}/${SERVER_NAME}.latency-ms.tsv"
            LATENCY_PNG_FILE="${MONITOR_OUTPUT_DIR}/${SERVER_NAME}.latency-hist.png"
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "pkill --full ${SERVER_NAME}" 2>/dev/null || true

            # Collect remote system metrics during this benchmark run.
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "~/bin/lightweight-system-monitor" > "${TSV_FILE}" &
            MONITOR_PID=$!

            # Start the server on the remote host
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "/home/martin/bin/${SERVER_NAME} ${REMOTE_PORT}" &

            trap 'ssh "${REMOTE_USER}@${REMOTE_HOST}" "pkill --full ${SERVER_NAME}" 2>/dev/null || true' EXIT

            (
                set -o xtrace
                tcp-echo-server-test-client \
                    --addr "${REMOTE_HOST}:${REMOTE_PORT}" \
                    --parallel-clients ${PARALLEL_CLIENTS} \
                    --requests-per-client ${REQUESTS_PER_CLIENT} \
                    --payload-repeat-count ${PAYLOAD_REPEAT_COUNT} \
                    --latency-ms-file "${LATENCY_MS_FILE}"
            )

            # Stop the server
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "pkill --full ${SERVER_NAME}" 2>/dev/null || true

            # Stop the monitor and flush captured output.
            kill "${MONITOR_PID}" 2>/dev/null || true
            wait "${MONITOR_PID}" 2>/dev/null || true

            # Render a PNG snapshot from the captured metrics.
            gnuplot \
                -e "datafile='${TSV_FILE}'" \
                -e "outputfile='${PNG_FILE}'" \
                "${SCRIPT_DIR}/presentation/visualize.gnuplot"

            # Render per-server request latency histogram with fixed 10ms buckets.
            gnuplot \
                -e "datafile='${LATENCY_MS_FILE}'" \
                -e "outputfile='${LATENCY_PNG_FILE}'" \
                -e "title='${SERVER_NAME} latency histogram (10ms buckets)'" \
                "${SCRIPT_DIR}/presentation/latency-histogram.gnuplot"
            trap - EXIT
        done
    done
done

echo "All benchmarks completed successfully! See $MONITOR_OUTPUT_DIR for results."
