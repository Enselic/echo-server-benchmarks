#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail -o xtrace

output_path="$1"

go build -o "$output_path" main.go
