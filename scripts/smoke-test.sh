#!/usr/bin/env bash
# Policy test matrix. For each case a real pod (own namespace / SA / pod name) logs in to OpenBao
# with a projected token (aud=bao) and probes paths; PASS = HTTP status matches the expectation.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
# Explicit context so the test never runs against whatever cluster the shell currently points at.
K="kubectl --context kind-$CLUSTER_NAME"

# run_case <ns> <sa> <pod> <auth:k8s|jwt> <login_want> <<< "want|METHOD|path" lines
run_case() {
  local ns=$1 sa=$2 pod=$3 auth=$4 login_want=$5 tests
  tests=$(cat)
  # Pods are immutable and logs are read after completion, so always start from a fresh pod.
  $K -n "$ns" delete pod "$pod" --ignore-not-found --wait=true >/dev/null
  $K -n "$ns" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $pod}
spec:
  serviceAccountName: $sa
  restartPolicy: Never
  # The default token has the API-server audience, which our role rejects on purpose. Only the
  # projected aud=bao token below is mounted, so the test can't accidentally pass with the wrong one.
  automountServiceAccountToken: false
  containers:
    - name: t
      image: curlimages/curl:8.10.1
      env:
        - {name: AUTH, value: "$auth"}
        - {name: LOGIN_WANT, value: "$login_want"}
        - name: TESTS
          value: |
$(sed 's/^/            /' <<<"$tests")
      command: [sh, -c]
      args:
        - |
          # In-cluster address: the bao container is on the kind network, trusted via the lab CA in bao-ca.
          B=https://bao:8200; C="--cacert /ca/ca.crt"
          JWT=\$(cat /var/run/secrets/bao/token)
          if [ "\$AUTH" = k8s ]; then LP=auth/kubernetes/login; ROLE=app; else LP=auth/jwt-k8s/login; ROLE=pod; fi
          R=\$(curl -s -w '\n%{http_code}' \$C -d "{\"role\":\"\$ROLE\",\"jwt\":\"\$JWT\"}" \$B/v1/\$LP)
          code=\$(echo "\$R" | tail -1)
          if [ "\$code" != "\$LOGIN_WANT" ]; then echo "FAIL login (want \$LOGIN_WANT got \$code)"; exit 0; fi
          echo "PASS login (\$code)"
          # A denied login is itself a valid expectation (team-c); stop here, there is no token to probe with.
          [ "\$code" = 200 ] || exit 0
          TOK=\$(echo "\$R" | head -n -1 | sed 's/.*"client_token":"\([^"]*\)".*/\1/')
          echo "\$TESTS" | while IFS='|' read -r want method path; do
            [ -z "\$want" ] && continue
            got=\$(curl -s -o /dev/null -w '%{http_code}' \$C -X \$method -H "X-Vault-Token: \$TOK" -d '{"data":{"x":"y"}}' \$B/v1/\$path)
            [ "\$got" = "\$want" ] && echo "PASS \$method \$path -> \$got" || echo "FAIL \$method \$path -> \$got (want \$want)"
          done
      volumeMounts:
        - {name: ca, mountPath: /ca}
        - {name: tok, mountPath: /var/run/secrets/bao}
  volumes:
    - name: ca
      configMap: {name: bao-ca}
    - name: tok
      projected:
        sources:
          - serviceAccountToken: {audience: bao, path: token, expirationSeconds: 600}
YAML
  $K -n "$ns" wait "pod/$pod" --for=jsonpath='{.status.phase}'=Succeeded --timeout=120s >/dev/null 2>&1 || true
  echo "== $ns/$sa pod=$pod auth=$auth"
  $K -n "$ns" logs "$pod" | sed 's/^/   /'
}

OUT=$(mktemp)
{
run_case team-a payments payments-0 k8s 200 <<'T'
200|GET|secret/data/apps/team-a/payments/config
403|GET|secret/data/apps/team-a/frontend/config
403|GET|secret/data/apps/team-b/billing/config
200|GET|secret/data/namespaces/team-a/shared
403|GET|secret/data/namespaces/team-b/shared
200|GET|database/creds/team-a-payments
403|GET|database/creds/team-a-frontend
403|POST|secret/data/apps/team-a/payments/config
403|LIST|secret/metadata/apps
403|GET|sys/mounts
403|GET|sys/policies/acl/k8s-app
403|GET|sys/audit
200|GET|auth/token/lookup-self
T
run_case team-a frontend frontend-0 k8s 200 <<'T'
200|GET|secret/data/apps/team-a/frontend/config
403|GET|secret/data/apps/team-a/payments/config
200|GET|database/creds/team-a-frontend
403|GET|database/creds/team-a-payments
T
run_case team-b billing billing-0 k8s 200 <<'T'
200|GET|secret/data/apps/team-b/billing/config
403|GET|secret/data/apps/team-a/payments/config
200|GET|secret/data/namespaces/team-b/shared
403|GET|secret/data/namespaces/team-a/shared
200|GET|database/creds/team-b-billing
T
# namespace not onboarded in the role's allow-list -> login itself is refused
run_case team-c rogue rogue-0 k8s 403 <<'T'
T
# pod-name identity via the jwt method
run_case team-a ledger ledger-0 jwt 200 <<'T'
200|GET|secret/data/pods/team-a/ledger-0/config
403|GET|secret/data/pods/team-a/ledger-1/config
403|GET|secret/data/apps/team-a/payments/config
T
run_case team-a ledger ledger-1 jwt 200 <<'T'
200|GET|secret/data/pods/team-a/ledger-1/config
403|GET|secret/data/pods/team-a/ledger-0/config
T
# jwt method reports a failed bound_claims check as 400
run_case team-c rogue rogue-jwt jwt 400 <<'T'
T
} | tee "$OUT"
echo
echo "passed: $(grep -c 'PASS' "$OUT")  failed: $(grep -c 'FAIL' "$OUT")"
# Non-zero exit on any FAIL so this works as a CI/pre-commit gate for policy changes.
! grep -q FAIL "$OUT"
