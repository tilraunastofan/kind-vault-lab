#!/usr/bin/env bash
CLUSTER_NAME="${CLUSTER_NAME:-vault-lab}"
BAO_CONTAINER="${BAO_CONTAINER:-bao}"

TF_ORG="${TF_ORG:-tilraunastofan}"
TF_WORKSPACE="${TF_WORKSPACE:-kind-vault-lab}"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
require_cmd() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"; done; }
