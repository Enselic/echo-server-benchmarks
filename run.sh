#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail -o xtrace

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Don't let fd count limit us
ulimit -n $(cat /proc/sys/fs/nr_open)

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
