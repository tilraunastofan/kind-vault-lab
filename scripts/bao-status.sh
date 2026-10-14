#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
if docker exec "$BAO_CONTAINER" bao status -format=json 2>/dev/null | grep -q '"sealed": false'; then
  log "OpenBao is unsealed"
else
  die "OpenBao is sealed or down — run: (cd $BAO_DIR && ./scripts/unseal.sh)"
fi
