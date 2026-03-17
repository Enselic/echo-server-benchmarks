#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# First run ./prepare-benchmarks.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PARALLEL_CLIENTS_VALUES="200"

# Format per entry: <requests-per-client>:<payload-repeat-count>
REQUESTS_PER_CLIENT_AND_PAYLOAD_REPEAT_COUNT_PAIRS="1000:1"

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
            sleep 0.1

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
            sleep 0.1

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

INDEX_HTML_FILE="${MONITOR_OUTPUT_DIR}/index.html"

html_escape() {
        # Escape a small set of HTML special characters for safe rendering.
        sed -e 's/&/\&amp;/g' \
                -e 's/</\&lt;/g' \
                -e 's/>/\&gt;/g' \
                -e 's/"/\&quot;/g' \
                -e "s/'/\&#39;/g"
}

benchmark_suffix_from_png() {
    local png_file_name base_name normalized_name

    png_file_name="$1"
    base_name="${png_file_name%.png}"
    normalized_name="${base_name%.latency-hist}"

    printf '%s\n' "${normalized_name##*.}"
}

benchmark_header_from_suffix() {
    local suffix part parallel_clients requests_per_client payload_repeat_count

    suffix="$1"

    for part in ${suffix//-/ }; do
        case "$part" in
            pc*) parallel_clients="${part#pc}" ;;
            rpc*) requests_per_client="${part#rpc}" ;;
            prc*) payload_repeat_count="${part#prc}" ;;
        esac
    done

    printf 'Parallel clients: %s | Requests per client: %s | Payload repeat count: %s\n' \
        "${parallel_clients:-unknown}" \
        "${requests_per_client:-unknown}" \
        "${payload_repeat_count:-unknown}"
}

image_title_from_png() {
    local png_file_name base_name normalized_name chart_label server_name title

    png_file_name="$1"
    base_name="${png_file_name%.png}"
    chart_label="System metrics"
    normalized_name="$base_name"

    if [[ "$base_name" == *.latency-hist ]]; then
        chart_label="Latency histogram"
        normalized_name="${base_name%.latency-hist}"
    fi

    server_name="${normalized_name%.*}"
    title="$(printf '%s' "${server_name}" | tr '._-' '   ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"

    printf '%s (%s)\n' "${title}" "${chart_label}"
}

{
        cat <<'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Echo Server Benchmark Overview</title>
    <style>
        :root {
            --bg: #f5f7fb;
            --card: #ffffff;
            --text: #1f2937;
            --muted: #4b5563;
            --border: #dbe3ef;
            --shadow: 0 8px 24px rgba(17, 24, 39, 0.08);
        }
        body {
            margin: 0;
            font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
            background: var(--bg);
            color: var(--text);
        }
        main {
            max-width: 1600px;
            margin: 0 auto;
            padding: 24px;
        }
        h1 {
            margin: 0 0 18px;
            font-size: 1.6rem;
        }
        p {
            margin: 0 0 20px;
            color: var(--muted);
        }
        .groups {
            display: flex;
            flex-direction: column;
            gap: 28px;
        }
        .group {
            display: flex;
            flex-direction: column;
            gap: 16px;
        }
        .group-header {
            background: var(--card);
            border: 1px solid var(--border);
            border-radius: 12px;
            box-shadow: var(--shadow);
            padding: 16px 18px;
        }
        .group-title {
            margin: 0;
            font-size: 1.05rem;
            line-height: 1.4;
        }
        .image-list {
            display: flex;
            flex-direction: column;
            gap: 18px;
        }
        .card {
            background: var(--card);
            border: 1px solid var(--border);
            border-radius: 12px;
            box-shadow: var(--shadow);
            padding: 12px;
        }
        .title {
            font-weight: 600;
            margin: 0 0 10px;
            font-size: 0.97rem;
            line-height: 1.3;
            word-break: break-word;
        }
        img {
            width: 100%;
            height: auto;
            display: block;
            border-radius: 8px;
            border: 1px solid #e5e7eb;
            background: #fff;
        }
        @media (max-width: 560px) {
            main {
                padding: 14px;
            }
            .group-header {
            padding: 14px;
            }
        }
    </style>
</head>
<body>
    <main>
        <h1>Echo Server Benchmark Overview</h1>
        <p>Generated from all PNG artifacts in this directory, grouped by benchmark parameters.</p>
        <section class="groups">
HTML_HEAD

        CURRENT_SUFFIX=""
        while IFS=$'\t' read -r BENCHMARK_SUFFIX PNG_FILE_NAME; do
            GROUP_HEADER="$(benchmark_header_from_suffix "${BENCHMARK_SUFFIX}")"
            TITLE="$(image_title_from_png "${PNG_FILE_NAME}")"
            SAFE_GROUP_HEADER="$(printf '%s' "${GROUP_HEADER}" | html_escape)"
            SAFE_TITLE="$(printf '%s' "${TITLE}" | html_escape)"
            SAFE_FILE_NAME="$(printf '%s' "${PNG_FILE_NAME}" | html_escape)"

            if [[ "${BENCHMARK_SUFFIX}" != "${CURRENT_SUFFIX}" ]]; then
                if [[ -n "${CURRENT_SUFFIX}" ]]; then
                    printf '        </div>\n'
                    printf '      </section>\n'
                fi

                printf '      <section class="group">\n'
                printf '        <header class="group-header">\n'
                printf '          <h2 class="group-title">%s</h2>\n' "${SAFE_GROUP_HEADER}"
                printf '        </header>\n'
                printf '        <div class="image-list">\n'
                CURRENT_SUFFIX="${BENCHMARK_SUFFIX}"
            fi

            printf '          <article class="card">\n'
            printf '            <h3 class="title">%s</h3>\n' "${SAFE_TITLE}"
            printf '            <a href="%s"><img src="%s" alt="%s"></a>\n' "${SAFE_FILE_NAME}" "${SAFE_FILE_NAME}" "${SAFE_TITLE}"
            printf '          </article>\n'
        done < <(
            find "${MONITOR_OUTPUT_DIR}" -maxdepth 1 -type f -name '*.png' -printf '%f\n' |
                while IFS= read -r PNG_FILE_NAME; do
                    printf '%s\t%s\n' "$(benchmark_suffix_from_png "${PNG_FILE_NAME}")" "${PNG_FILE_NAME}"
                done |
                sort
        )

        if [[ -n "${CURRENT_SUFFIX}" ]]; then
            printf '        </div>\n'
            printf '      </section>\n'
        fi

        cat <<'HTML_TAIL'
        </section>
    </main>
</body>
</html>
HTML_TAIL
} > "${INDEX_HTML_FILE}"

echo "All benchmarks completed successfully! See

    file://wsl.localhost/Ubuntu-24.04/$MONITOR_OUTPUT_DIR

for results."
