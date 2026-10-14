#!/usr/bin/env bash
# Idempotently create the HCP Terraform workspace. Execution mode is "local":
# HCP's remote runners can't reach the laptop's kind API server or OpenBao, so
# HCP only stores state/locks and plans/applies run on this machine.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
require_cmd curl jq
: "${TERRAFORM_TOKEN:?TERRAFORM_TOKEN must be set}"
api="https://app.terraform.io/api/v2"
h=(-H "Authorization: Bearer $TERRAFORM_TOKEN" -H "Content-Type: application/vnd.api+json")

code=$(curl -s -o /dev/null -w '%{http_code}' "${h[@]}" "$api/organizations/$TF_ORG/workspaces/$TF_WORKSPACE")
if [ "$code" = 200 ]; then
  log "workspace $TF_WORKSPACE exists"
else
  log "creating workspace $TF_WORKSPACE"
  curl -sf "${h[@]}" -X POST "$api/organizations/$TF_ORG/workspaces" -d "$(jq -n --arg n "$TF_WORKSPACE" \
    '{data:{type:"workspaces",attributes:{name:$n,"execution-mode":"local"}}}')" >/dev/null
fi
