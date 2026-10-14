#!/usr/bin/env bash
# Remove the bao containers. Data volume and .secrets are kept (use bao:purge to wipe).
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -f bao/compose.yaml down
