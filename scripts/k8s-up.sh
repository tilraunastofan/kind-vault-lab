#!/usr/bin/env bash
# Idempotent: prepare the two machine-local inputs Kustomize needs, then `kubectl apply -k`.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
require_cmd kubectl openssl
K="kubectl --context kind-$CLUSTER_NAME"

# The lab CA is generated per laptop (gitignored), so the ClusterTrustBundle that publishes it cluster-wide is
# rendered here rather than committed. Signer-linked on purpose: only principals with `attest` on this signer
# name may create or change it, and pods select it by signerName instead of trusting a free-form bundle name.
# The name must be the signer name with "/" turned into ":" (API rule). The CA needs basicConstraints CA:TRUE or
# the API server rejects the bundle (scripts/bao-up.sh sets it).
[ -f bao/pki/ca.crt ] || die "bao/pki/ca.crt missing: run 'task bao:up' first"
{
  cat <<'YAML'
apiVersion: certificates.k8s.io/v1
kind: ClusterTrustBundle
metadata:
  name: bao.lab.internal:server-ca:v1
  labels:
    trust: bao
spec:
  signerName: bao.lab.internal/server-ca
  trustBundle: |
YAML
  sed 's/^/    /' bao/pki/ca.crt
} > k8s/bao-ca/clustertrustbundle.yaml

# Generate the postgres root password once. Never regenerate: the password is also what terraform reads back and gives OpenBao,
# and a new one would roll the pod while OpenBao still holds the old one.
[ -s k8s/data/pg-root.env ] || { log "generating postgres root password"; printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 16)" > k8s/data/pg-root.env; chmod 600 k8s/data/pg-root.env; }

$K apply -k k8s

# Terraform needs these two to exist before it configures OpenBao: the token controller fills the SA token
# Secret asynchronously, and the database engine connects to postgres when its connection is created.
$K -n data rollout status deploy/postgres --timeout=180s
until [ -n "$($K -n kube-system get secret bao-auth-token -o jsonpath='{.data.token}')" ]; do sleep 1; done
