#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# First run ./prepare-benchmarks.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PARALLEL_CLIENTS_VALUES="20"

# Format per entry: <requests-per-client>:<payload-repeat-count>
REQUESTS_PER_CLIENT_AND_PAYLOAD_REPEAT_COUNT_PAIRS="100000:1"

REMOTE_PORT=9092
RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
MONITOR_OUTPUT_DIR="/tmp/echo-server-benchmarks-${RUN_TIMESTAMP}"

# We need many fds, so increase to max.
ulimit -n $(cat /proc/sys/fs/nr_open)

# Build test client from source
echo "Building tcp-echo-server-test-client..."
(cd "$SCRIPT_DIR/test-client" && cargo build --release)
cp "$SCRIPT_DIR/test-client/target/release/tcp-echo-server-test-client" "$SCRIPT_DIR/build/tcp-echo-server-test-client"
PATH="$SCRIPT_DIR/build:$PATH"
mkdir -p "${MONITOR_OUTPUT_DIR}"

LATENCY_MS_FILES=()
LATENCY_PNG_FILES=()
LATENCY_TITLES=()

for PARALLEL_CLIENTS in $PARALLEL_CLIENTS_VALUES; do
    for REQUEST_PAYLOAD_PAIR in $REQUESTS_PER_CLIENT_AND_PAYLOAD_REPEAT_COUNT_PAIRS; do
        IFS=':' read -r REQUESTS_PER_CLIENT PAYLOAD_REPEAT_COUNT <<<"$REQUEST_PAYLOAD_PAIR"

        for SERVER in "$SCRIPT_DIR"/servers/*-tcp-echo-server; do
            SERVER_NAME=$(basename $SERVER)
            BENCHMARK_SUFFIX="pc${PARALLEL_CLIENTS}-rpc${REQUESTS_PER_CLIENT}-prc${PAYLOAD_REPEAT_COUNT}"
            TSV_FILE="${MONITOR_OUTPUT_DIR}/${SERVER_NAME}.${BENCHMARK_SUFFIX}.tsv"
            PNG_FILE="${MONITOR_OUTPUT_DIR}/${SERVER_NAME}.${BENCHMARK_SUFFIX}.png"
            LATENCY_MS_FILE="${MONITOR_OUTPUT_DIR}/${SERVER_NAME}.${BENCHMARK_SUFFIX}.latency-ms.tsv"
            LATENCY_PNG_FILE="${MONITOR_OUTPUT_DIR}/${SERVER_NAME}.${BENCHMARK_SUFFIX}.latency-hist.png"
            LATENCY_MS_FILES+=("${LATENCY_MS_FILE}")
            LATENCY_PNG_FILES+=("${LATENCY_PNG_FILE}")
            LATENCY_TITLES+=("${SERVER_NAME} latency histogram (10ms buckets)")
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "pkill --full ${SERVER_NAME}" 2>/dev/null || true

            # Collect remote system metrics during this benchmark run.
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "~/bin/lightweight-system-monitor" "--mem-available-baseline-kb" "6900000" > "${TSV_FILE}" &
            MONITOR_PID=$!

            # Let system metrics stabalize before starting the server and client.
            sleep 5

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

            # Let system metrics stabalize before stopping monitoring.
            sleep 5

            # Stop the monitor and flush captured output.
            kill "${MONITOR_PID}" 2>/dev/null || true
            wait "${MONITOR_PID}" 2>/dev/null || true

            # Render a PNG snapshot from the captured metrics.
            gnuplot \
                -e "datafile='${TSV_FILE}'" \
                -e "outputfile='${PNG_FILE}'" \
                "${SCRIPT_DIR}/presentation/visualize.gnuplot"
            trap - EXIT
        done
    done
done

if ((${#LATENCY_MS_FILES[@]} > 0)); then
    OBSERVED_MAX_LATENCY=$(awk '
        BEGIN { max = 0; found = 0 }
        NF {
            value = $1 + 0
            if (!found || value > max) {
                max = value
                found = 1
            }
        }
        END {
            if (!found) {
                print "1"
                exit
            }
            if (max > int(max)) {
                print int(max) + 1
            } else {
                print int(max)
            }
        }
    ' "${LATENCY_MS_FILES[@]}")

    for index in "${!LATENCY_MS_FILES[@]}"; do
        gnuplot \
            -e "datafile='${LATENCY_MS_FILES[$index]}'" \
            -e "outputfile='${LATENCY_PNG_FILES[$index]}'" \
            -e "title='${LATENCY_TITLES[$index]}'" \
            -e "max_latency=${OBSERVED_MAX_LATENCY}" \
            "${SCRIPT_DIR}/presentation/latency-histogram.gnuplot"
    done
fi

echo "All benchmarks completed successfully! See

    file://wsl.localhost/Ubuntu-24.04/$MONITOR_OUTPUT_DIR

for results."
