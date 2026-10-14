#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
# Disconnect first: `kind delete` removes the kind network, which fails or is skipped while another
# container is still attached to it.
docker network disconnect kind "$BAO_CONTAINER" 2>/dev/null || true
kind delete cluster --name "$CLUSTER_NAME"
