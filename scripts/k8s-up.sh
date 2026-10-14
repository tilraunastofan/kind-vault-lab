#!/usr/bin/env bash
# Idempotent: prepare the two machine-local inputs Kustomize needs, then `kubectl apply -k`.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
require_cmd kubectl openssl
K="kubectl --context kind-$CLUSTER_NAME"

# Kustomize can only read files below its own directory, so the lab CA (generated per laptop, gitignored)
# is copied next to the generator that turns it into the bao-ca ConfigMaps.
[ -f bao/pki/ca.crt ] || die "bao/pki/ca.crt missing: run 'task bao:up' first"
cp bao/pki/ca.crt k8s/bao-ca/ca.crt

# Generate the postgres root password once. Never regenerate: the password is also what terraform reads back and gives OpenBao,
# and a new one would roll the pod while OpenBao still holds the old one.
[ -s k8s/data/pg-root.env ] || { log "generating postgres root password"; printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 16)" > k8s/data/pg-root.env; chmod 600 k8s/data/pg-root.env; }

$K apply -k k8s

# Terraform needs these two to exist before it configures OpenBao: the token controller fills the SA token
# Secret asynchronously, and the database engine connects to postgres when its connection is created.
$K -n data rollout status deploy/postgres --timeout=180s
until [ -n "$($K -n kube-system get secret bao-auth-token -o jsonpath='{.data.token}')" ]; do sleep 1; done
