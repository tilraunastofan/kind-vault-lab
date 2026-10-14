# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A **learning lab** (dev sandbox, laptop with 16GB RAM) for experimenting with Kubernetes <-> OpenBao integration and "audit-grade" policy patterns. Tokens and credentials are pre-approved for agent handling here (README). Generated credentials go in `./CREDENTIALS.md` (gitignored). Comments in code should explain *why*, not how.

## Commands

All operations go through `task` (Taskfile.yaml); the lab must stay idempotent and bootstrappable from zero.

- `task up` — bao -> kind cluster -> `kubectl apply -k k8s` -> HCP TF workspace -> `terraform apply`
- `task k8s:apply` / `task k8s:diff` — all Kubernetes-only objects are plain YAML in `k8s/` applied with Kustomize (`kubectl apply -k`); Terraform does NOT manage any k8s resources
- `task smoke` — policy test matrix; exits non-zero on any FAIL. There is no single-test mode: edit/comment cases in `scripts/smoke-test.sh` (one `run_case` per pod).
- `task tf:plan` / `task tf:apply` — Terraform is OpenBao-only. It has no `kubernetes_*` resources, only read-only data sources in `terraform/cluster.tf` (cluster CA, `bao-auth` reviewer token, postgres password) plus the kind SA public key, so `task k8s:apply` must run first. Run it via `task` (injects `VAULT_TOKEN` from `.secrets/init.json`); bare `terraform` fails with "no vault token set". `TERRAFORM_TOKEN` must be in the environment.
- `task audit` — pretty-printed OpenBao audit log (`scripts/audit-pretty.jq`)
- `task down` (deletes the kind cluster only), `task bao:down` (keeps data), `task bao:purge` (wipes OpenBao data, keys, certs)

## Architecture

Two things run side by side; the interesting part is how they reach each other.

- **OpenBao runs outside the cluster** as a Docker Compose stack (`bao/`: `bao` + `bao-unseal` sidecar) under OrbStack. It is owned by this repo (the old `~/bao` stack is unused; don't start it, it uses the same container name/port). One key share; the sidecar auto-unseals from `.secrets/unseal.key`. Keys/root token: `.secrets/init.json`. Dev only.
- **Three addresses for the same server:** laptop -> `https://bao.orb.local` (OrbStack HTTPS, system-trusted, no port); pods -> `https://bao:8200` (lab CA in `bao/pki/`, distributed as ConfigMap `bao-ca`); bao -> API server `https://vault-lab-control-plane:6443` (TokenReview). This works because `bao` is attached to the `kind` docker network. Recreating the container drops that attachment; `scripts/bao-up.sh` and `cluster-up.sh` re-attach it.
- **Terraform state is in HCP Terraform** (org `tilraunastofan`, workspace `kind-vault-lab`) with **local execution** because HCP runners can't reach the laptop. The workspace is created by `scripts/tfc-workspace-up.sh`.
- **Audit device is declarative** in `bao/bao.hcl` (OpenBao rejects API-enabled audit devices); changing it needs a container recreate.

### Policy model (the core of the lab, see `docs/POLICIES.md`)

The **kv path layout is the access-control model**: `terraform/policies.tf` templates policies on the login's entity-alias metadata (`{{identity.entity.aliases.<mount accessor>.metadata.*}}`), and `terraform/data.tf` lays out paths to match (`secret/apps/<ns>/<sa>`, `secret/namespaces/<ns>`, `secret/pods/<ns>/<pod>`, `database/creds/<ns>-<sa>`). Change one side without the other and tenants gain or lose access. Two auth mounts: `kubernetes` (ns + serviceaccount) and `jwt-k8s` (adds pod name from projected-token claims). Onboarding a service = SA + data + DB role, no policy edit. Only namespaces in `var.onboarded_namespaces` (variables.tf; keep in sync with `k8s/tenants/`) may log in; `team-c` is a deliberate negative control.

`scripts/smoke-test.sh` is both the test suite and the executable spec: pods log in with an `aud=bao` projected token and probe allowed/denied paths. Add a matrix row whenever policy changes. Gotchas it encodes: permitted-but-missing path = 404, denied = 403 (seed data so 200-vs-403 is unambiguous); a failed JWT `bound_claims` check returns 400.

Next-step ideas live in `docs/IDEAS.md`.
