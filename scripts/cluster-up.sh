#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
require_cmd kind kubectl docker

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "kind cluster '$CLUSTER_NAME' already exists"
else
  kind create cluster --config cluster/kind-config.yaml
fi
kubectl cluster-info --context "kind-$CLUSTER_NAME" >/dev/null

# Make the existing OpenBao container reachable from the cluster: attach it to
# the `kind` docker network (alias `bao` is in the server cert SANs).
if docker inspect -f '{{json .NetworkSettings.Networks}}' "$BAO_CONTAINER" | grep -q '"kind"'; then
  log "$BAO_CONTAINER already on the kind network"
else
  docker network connect kind "$BAO_CONTAINER"
fi
