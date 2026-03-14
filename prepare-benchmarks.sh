#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# deploy servers
if [ "$REMOTE_HOST" = "" ] || [ "$REMOTE_USER" = "" ]; then
    echo "Error: REMOTE_HOST and REMOTE_USER environment variables must be set for deployment"
    exit 1
fi
./servers/deploy.sh
