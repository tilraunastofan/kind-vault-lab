#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
docker network disconnect kind "$BAO_CONTAINER" 2>/dev/null || true
kind delete cluster --name "$CLUSTER_NAME"
