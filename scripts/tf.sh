#!/usr/bin/env bash
# Run terraform with everything it needs from outside Terraform. Terraform only manages OpenBao, so the
# cluster-derived values (CA, reviewer token, SA signing key) and the postgres password come in as variables
# instead of via kubernetes/external providers.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
require_cmd kubectl jq docker terraform
K="kubectl --context kind-$CLUSTER_NAME"

export VAULT_TOKEN="$(jq -r .root_token .secrets/init.json)"
if [ "${1:-}" != init ]; then
  export TF_VAR_k8s_ca_cert="$($K -n kube-system get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')"
  export TF_VAR_k8s_reviewer_jwt="$($K -n kube-system get secret bao-auth-token -o jsonpath='{.data.token}' | base64 -d)"
  # OpenBao can't fetch /openid/v1/jwks (needs auth), so the API server's SA public key is pinned instead.
  export TF_VAR_k8s_sa_pubkey="$(docker exec "$CLUSTER_NAME-control-plane" cat /etc/kubernetes/pki/sa.pub)"
  export TF_VAR_pg_root_password="$(sed -n 's/^POSTGRES_PASSWORD=//p' k8s/data/pg-root.env)"
fi
cd terraform
exec terraform "$@"
