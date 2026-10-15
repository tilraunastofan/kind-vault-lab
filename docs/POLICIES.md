# OpenBao <-> Kubernetes policy patterns

Run `task smoke` to execute the allow/deny matrix (`scripts/smoke-test.sh`) from
real pods. Diagrams: `DIAGRAMS.md`. Trust setup: `TRUST-BOOTSTRAP.md`, `CLUSTER-TRUST.md`, `K8S-1.37.md`, `PROJECTED-VOLUMES.md`. More
ideas: `IDEAS.md`, `PKI.md`. Config:
`terraform/{auth,policies,data}.tf` (OpenBao) and `k8s/` (Kustomize: namespaces, service accounts, postgres). Audit log: `task audit`
(`bao/bao.hcl`).

## Pattern 1: identity = namespace + serviceaccount (`kubernetes` auth)

One role (`app`), one templated policy (`k8s-app`). The policy resolves the
caller's identity from the login's entity-alias metadata, so **no per-service role
or policy exists**:

| Path                            | Who can read                                     |
| ------------------------------- | ------------------------------------------------ |
| `secret/data/apps/<ns>/<sa>/*`  | exactly that ServiceAccount                      |
| `secret/data/namespaces/<ns>/*` | any SA in that namespace                         |
| `database/creds/<ns>-<sa>`      | that SA (dynamic Postgres user, 5m TTL, max 15m) |

⭐ **Onboarding a service = create SA (`k8s/tenants/<ns>/serviceaccounts.yaml`) + kv data and DB role (`terraform/data.tf`). No policy edit.**

## Pattern 2: identity = pod name (`jwt` auth)

The kubernetes method can't see the pod name. Projected SA tokens carry
`kubernetes.io/pod/{name,uid}`, so a `jwt` mount validates them (issuer + SA
public key) and maps claims to alias metadata. Entity alias = pod UID, so
metadata can't collide between pods of the same SA. Policy `k8s-pod` ->
`secret/data/pods/<ns>/<pod>/*`. ⚠️ Pod names are only stable for StatefulSets; for
Deployments prefer Pattern 1. Trade-off: one OpenBao entity per pod UID (clean
up with entity garbage-collection in production).

## 🛡️ Audit checklist this lab satisfies

- [x] Audit device enabled, declarative in config (OpenBao refuses API-enabled
      devices). `task audit`
- [x] No wildcard identity: `bound_service_account_namespaces` is an explicit
      allow-list (also bound claim on `jwt`); `team-c` is refused at login
      (tested)
- [x] Token audience pinned (`aud=bao`), not the API-server audience; projected
      tokens, 10 min lifetime
- [x] `token_no_default_policy = true`; policies are read-only, fully anchored,
      no `sys/*`, no `list`, no `sudo`
- [x] Short TTLs: token 5m / max 15m; DB creds 5m / max 15m (revoked = role
      dropped)
- [x] Cross-tenant reads, writes, listing and `sys/*` access are tested as
      denied
- [x] Policies and roles are code (Terraform), reviewed via git
- [x] Named `lab-admin` policy exists instead of day-to-day root use
- [ ] 🚧 Not demonstrated (production TODO): rotate DB root credential
      (`database/rotate-root/orders`), revoke the root token and use `lab-admin`
      via OIDC/userpass, auto-unseal via KMS/transit instead of a key file, ship
      audit log off-box, `token_bound_cidrs`, sentinel/EGP-style policies if
      licensed

## ⚠️ Gotchas found while building this

- OpenBao rejects `vault_audit`/API audit enablement: declare `audit "file" ...`
  in `bao.hcl`.
- `jwt` roles without `bound_claims` accept any namespace; a missing allow-list
  only showed up because the matrix had a `team-c` negative control. Failed
  claim checks return 400, not 403.
- Reading a non-existent but permitted path returns 404, denied returns 403:
  always seed data so 200-vs-403 tests are unambiguous.
