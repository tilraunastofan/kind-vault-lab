# HANDOFF

State at the end of the session (2026-10-15). Read `CLAUDE.md` first; it has the commands and architecture.

## Where things stand

- `main` is pushed to `tilraunastofan/kind-vault-lab`; nothing is uncommitted. `CLAUDE.md` includes the user's
  guideline to prefer many small files in a directory structure over long files.
- The lab is **running** right now: kind cluster `vault-lab` (2 nodes, Kubernetes v1.37.0, etcd 3.7.0), containers
  `bao` + `bao-unseal` (OpenBao 2.7.0, unsealed), Terraform state in HCP workspace `tilraunastofan/kind-vault-lab`.
- Last verified: `task smoke` passed 34/34 and `terraform plan` showed no changes.

## What the lab is

Kubernetes <-> OpenBao experiments with audit-grade, templated policies. One generic login role per auth method; the
policies resolve identity (namespace / service account / pod name) from the login's alias metadata, so onboarding a
service needs no policy edit. Details: `docs/POLICIES.md`, `docs/TRUST-BOOTSTRAP.md`, `docs/DIAGRAMS.md`.

## How to resume

```sh
export TERRAFORM_TOKEN=...      # HCP Terraform; must be in the environment
task up                          # idempotent: bao -> kind -> kubectl apply -k k8s -> HCP workspace -> terraform apply
task smoke                       # 34 allow/deny checks from real pods
task audit                       # pretty audit log
```

From zero on a new laptop: the same `task up` (generates the lab CA, initialises OpenBao, creates the cluster).
Credentials are generated locally and gitignored; **locations, not values**: OpenBao unseal key and root token in
`.secrets/` (`init.json`, `unseal.key`), Postgres root password in `k8s/data/pg-root.env`, everything listed in
`CREDENTIALS.md`.

## Decisions made (and why)

- **OpenBao is owned by this repo** (`bao/`), not `~/bao`. The old `~/bao` stack is unused; do not start it (same
  container name and port). Auto-unseal is a sidecar reading a key file: dev only.
- **Kubernetes objects = Kustomize (`k8s/`, `kubectl apply -k`); Terraform = OpenBao only.** Terraform has no
  `kubernetes_*` resources, only read-only data sources in `terraform/cluster.tf` (this replaced a `kubectl`-based
  wrapper script, rejected as inelegant/insecure for production).
- **Terraform runs with local execution** in HCP (HCP runners cannot reach the laptop).
- **Audit device is declared in `bao/bao.hcl`**: OpenBao refuses API-enabled audit devices.
- **Cluster-wide CA trust uses one ClusterTrustBundle** instead of a ConfigMap per namespace (`docs/CLUSTER-TRUST.md`).
  This exposed and fixed a bug: the lab CA lacked `basicConstraints CA:TRUE`.
- **Host-side address is `https://bao.orb.local`** (OrbStack, system-trusted); pods use `https://bao:8200`.

## Known issues / open questions

- **One unexplained smoke failure:** the first `task smoke` right after a from-zero `task up` reported 1 FAIL out of
  34; it passed on every rerun and the failing check was not captured. Suspect pod start-up timing (image pull) in
  `scripts/smoke-test.sh`. If it recurs, save the output of the failing case.
- `kubectl explain` on 1.37.0 still labels the `clusterTrustBundle` projection "Alpha"; it works without any feature
  gate. Treated as stale doc text.
- The `kubernetes` auth method relies on a long-lived reviewer token (in OpenBao config and Terraform state).
  Production should use the `jwt` method with the cluster's public OIDC issuer (`docs/TRUST-BOOTSTRAP.md`).
- Production gaps deliberately left out: root token not revoked, no DB root rotation, key-file unseal, audit log not
  shipped off the box (`docs/POLICIES.md` checklist).

## Backlog (nothing started)

See `docs/IDEAS.md`. Suggested order: per-service-account PKI role (`docs/PKI.md`), per-identity kill switch (disable
an entity), token constraints (`token_bound_cidrs`, wrapping, parameter limits), metadata/group-driven policy.
Also: OpenBao as the signer behind Kubernetes 1.37 Pod Certificates (`docs/CLUSTER-TRUST.md`).
`docs/K8S-1.37.md` records that Pod-Level Resource Managers were evaluated and parked.

## Gotchas for the next session

- Run Terraform through `task tf:*` (injects `VAULT_TOKEN` from `.secrets/init.json`); bare `terraform` fails.
- `task k8s:apply` must precede Terraform: the data sources read objects Kustomize creates.
- Recreating the `bao` container drops it from the `kind` Docker network; `scripts/bao-up.sh` and
  `scripts/cluster-up.sh` re-attach it. After regenerating certs, `bao-up.sh` force-recreates the containers.
- Keep `var.onboarded_namespaces` (`terraform/variables.tf`) in sync with `k8s/tenants/`.
- Policy paths (`terraform/policies.tf`) and kv layout (`terraform/data.tf`) are one design; change both together and
  add a `scripts/smoke-test.sh` row.
- In this shell `k` is an alias and zsh does not word-split variables, so use a function (e.g. `kc()`) or full
  `kubectl --context kind-vault-lab ...` in ad-hoc commands.
