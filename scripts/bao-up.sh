#!/usr/bin/env bash
# Idempotent: PKI -> container + auto-unsealer -> init (first run) -> kv/userpass bootstrap.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
require_cmd docker openssl jq curl
mkdir -p .secrets bao/pki

# --- PKI: local CA + server cert (only if missing) ---
if [ ! -f bao/pki/bao.crt ]; then
  log "generating CA + bao server cert"
  cd bao/pki
  openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 3650 -subj "/CN=bao-lab dev CA" 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -keyout bao.key -out bao.csr -subj "/CN=bao.orb.local" 2>/dev/null
  printf 'subjectAltName=DNS:bao.orb.local,DNS:bao,DNS:localhost,IP:127.0.0.1\n' > san.cnf
  openssl x509 -req -in bao.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out bao.crt -days 825 -extfile san.cnf 2>/dev/null
  rm -f bao.csr san.cnf ca.srl
  chmod 644 bao.key   # container user must read it; dev only
  cd ../..
fi

docker compose -f bao/compose.yaml up -d

until curl -s -o /dev/null https://bao.orb.local/v1/sys/health; do sleep 1; done

B() { docker exec -i -e BAO_TOKEN="$(jq -r .root_token .secrets/init.json)" bao bao "$@"; }

if [ ! -s .secrets/init.json ]; then
  log "initialising OpenBao (1 key share)"
  docker exec bao bao operator init -key-shares=1 -key-threshold=1 -format=json > .secrets/init.json
  chmod 600 .secrets/init.json
  jq -r '.unseal_keys_b64[0]' .secrets/init.json > .secrets/unseal.key
  chmod 600 .secrets/unseal.key
fi

log "waiting for auto-unseal"
until curl -s https://bao.orb.local/v1/sys/health | jq -e '.sealed == false' >/dev/null 2>&1; do sleep 2; done

B auth list -format=json | jq -e 'has("userpass/")' >/dev/null || B auth enable userpass
B secrets list -format=json | jq -e 'has("secret/")' >/dev/null || B secrets enable -path=secret -version=2 kv
B policy write admin - >/dev/null <<'POLICY'
path "*" { capabilities = ["create","read","update","delete","list","sudo"] }
POLICY
B write auth/userpass/users/jakob password=foobar token_policies=admin >/dev/null
log "OpenBao ready: https://bao.orb.local"

# Re-attach to the kind network if the cluster exists (recreating the container drops it).
if docker network inspect kind >/dev/null 2>&1 && ! docker inspect -f '{{json .NetworkSettings.Networks}}' bao | grep -q '"kind"'; then
  docker network connect kind bao
fi
