#!/usr/bin/env bash

TEST_USER=${TEST_USER:-"martin"}
TEST_HOST=${TEST_HOST:-"192.168.0.104"}

SSH_USER_AND_HOST="${TEST_USER}@${TEST_HOST}"
DEPLOY_DIR="~/bin"

OUTPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"

SERVER_PORT_BASE=7020

servers_to_test=(
    go-tcp-echo-server
    rust-tokio-tcp-echo-server
    rust-threaded-tcp-echo-server
)

# Returns a unique port for a given server index (0-based)
server_port_for_index() {
    echo $((SERVER_PORT_BASE + 1 + $1))
}
