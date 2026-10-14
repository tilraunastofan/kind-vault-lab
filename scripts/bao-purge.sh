#!/usr/bin/env bash
# DELETE all OpenBao data, keys and certs. Next `task bao:up` re-initialises from zero.
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -f bao/compose.yaml down -v
rm -rf .secrets bao/pki
