#!/usr/bin/env bash
# Idempotent: PKI -> container + auto-unsealer -> init (first run) -> kv/userpass bootstrap.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
require_cmd docker openssl jq curl
mkdir -p .secrets bao/pki

# --- PKI: local CA + server cert (only if missing) ---
# Why our own TLS when OrbStack already serves https://bao.orb.local? Pods can't resolve that name;
# they reach the container directly as https://bao:8200 on the kind network and need a CA to trust there.
if [ ! -f bao/pki/bao.crt ]; then
  log "generating CA + bao server cert"
  cd bao/pki
  # CA:TRUE matters: Kubernetes ClusterTrustBundle (k8s/bao-ca) rejects certificates without the CA bit, and strict
  # TLS clients may too; a bare `openssl req -x509` does not always set it.
  openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 3650 -subj "/CN=bao-lab dev CA" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -keyout bao.key -out bao.csr -subj "/CN=bao.orb.local" 2>/dev/null
  printf 'subjectAltName=DNS:bao.orb.local,DNS:bao,DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' > san.cnf
  openssl x509 -req -in bao.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out bao.crt -days 825 -extfile san.cnf 2>/dev/null
  rm -f bao.csr san.cnf ca.srl
  chmod 644 bao.key   # the container runs as a non-root user that doesn't own the bind-mounted key; dev only
  cd ../..
  NEW_CERTS=1
fi

# New certs need a recreate: bao reads its cert at startup, and the sidecar's single-file bind mount of ca.crt
# keeps pointing at the old (deleted) inode.
docker compose -f bao/compose.yaml up -d ${NEW_CERTS:+--force-recreate}

until curl -s -o /dev/null https://bao.orb.local/v1/sys/health; do sleep 1; done

# Runs bao CLI inside the container: no bao binary or TLS/CA setup needed on the host.
B() { docker exec -i -e BAO_TOKEN="$(jq -r .root_token .secrets/init.json)" bao bao "$@"; }

# Init only once: re-running `operator init` on an initialised cluster errors, and the generated
# keys exist exactly once, so losing .secrets/ means `task bao:purge` + start over.
if [ ! -s .secrets/init.json ]; then
  log "initialising OpenBao (1 key share)"
  docker exec bao bao operator init -key-shares=1 -key-threshold=1 -format=json > .secrets/init.json
  chmod 600 .secrets/init.json
  # Separate file so the unseal sidecar can mount just the key without being handed the root token.
  jq -r '.unseal_keys_b64[0]' .secrets/init.json > .secrets/unseal.key
  chmod 600 .secrets/unseal.key
fi

# The bao-unseal sidecar does the unsealing; we only wait, so the API calls below don't hit a sealed server.
log "waiting for auto-unseal"
until curl -s https://bao.orb.local/v1/sys/health | jq -e '.sealed == false' >/dev/null 2>&1; do sleep 2; done

B auth list -format=json | jq -e 'has("userpass/")' >/dev/null || B auth enable userpass
B secrets list -format=json | jq -e 'has("secret/")' >/dev/null || B secrets enable -path=secret -version=2 kv
# Lab-wide admin policy for the userpass user (humans). Apps never get this; see terraform/policies.tf.
B policy write admin - >/dev/null <<'POLICY'
path "*" { capabilities = ["create","read","update","delete","list","sudo"] }
POLICY
B write auth/userpass/users/jakob password=foobar token_policies=admin >/dev/null
log "OpenBao ready: https://bao.orb.local"

# Re-attach to the kind network if the cluster exists (recreating the container drops it).
if docker network inspect kind >/dev/null 2>&1 && ! docker inspect -f '{{json .NetworkSettings.Networks}}' bao | grep -q '"kind"'; then
  docker network connect kind bao
fi
