#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail -o xtrace

output_path="$1"

rustc -O main.rs -o "$output_path"
