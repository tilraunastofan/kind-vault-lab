#!/usr/bin/env bash
# A pod running as demo/demo-app logs in with its SA JWT and reads secret/demo/config.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
kubectl --context "kind-$CLUSTER_NAME" -n demo delete pod smoke --ignore-not-found >/dev/null
kubectl --context "kind-$CLUSTER_NAME" -n demo apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: smoke}
spec:
  serviceAccountName: demo-app
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.10.1
      command: [sh, -c]
      args:
        - |
          set -e
          B=https://bao:8200
          JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
          T=$(curl -sf --cacert /ca/ca.crt -d "{\"role\":\"demo-app\",\"jwt\":\"$JWT\"}" $B/v1/auth/kubernetes/login | sed 's/.*"client_token":"\([^"]*\)".*/\1/')
          curl -sf --cacert /ca/ca.crt -H "X-Vault-Token: $T" $B/v1/secret/data/demo/config
          echo
      volumeMounts: [{name: ca, mountPath: /ca}]
  volumes:
    - name: ca
      configMap: {name: bao-ca}
YAML
kubectl --context "kind-$CLUSTER_NAME" -n demo wait pod/smoke --for=jsonpath='{.status.phase}'=Succeeded --timeout=90s
kubectl --context "kind-$CLUSTER_NAME" -n demo logs smoke
