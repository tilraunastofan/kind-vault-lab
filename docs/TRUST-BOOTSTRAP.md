# How Kubernetes first authenticates to OpenBao

OpenBao runs **outside** the cluster, so neither side has an identity on the
other by default. This page explains the first contact, the trust that must
exist before it, and who bootstraps the bootstrap. Flow diagrams: `DIAGRAMS.md`.
Policy details: `POLICIES.md`.

## First point of contact

The pod logs in. It sends its own service-account token (a JWT) to
`POST https://bao:8200/v1/auth/kubernetes/login` with `{role: app, jwt}`.
OpenBao never calls the pod first, and ⭐ **the pod holds no pre-shared secret**.

### ⭐ Why there is no "secret zero" to distribute

The kubelet projects a token into the pod, signed by the API server, valid 10
minutes, minted with audience `bao` (`serviceAccountToken` projection; see
`scripts/smoke-test.sh`). Nobody generates, ships or stores it: a pod that
exists can present one. OpenBao accepts it only if the Kubernetes API server
vouches for it.

## Trust that must exist beforehand (cluster side by Kustomize, OpenBao side by Terraform)

| # | Direction                  | What                                                  | Where                                                                             |
| - | -------------------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------- |
| 1 | OpenBao trusts the cluster | API server address + CA + a **reviewer token**        | `k8s/bao-auth/` (SA + token + RBAC), `terraform/auth.tf` (`vault_kubernetes_auth_backend_config`) |
| 2 | Pods trust OpenBao         | lab CA as one cluster-wide ClusterTrustBundle         | `k8s/bao-ca/` (generated per laptop by `scripts/k8s-up.sh`), CA made by `scripts/bao-up.sh` |
| 3 | Network path               | `bao` container attached to the `kind` docker network | `scripts/cluster-up.sh`, `scripts/bao-up.sh`                                      |

### 1. OpenBao trusts the cluster

- OpenBao is given the API server address
  (`https://vault-lab-control-plane:6443`, reachable over the kind network) and
  its CA.
- It also gets a **reviewer credential**: the long-lived token of service
  account `bao-auth` in `kube-system`, bound to `system:auth-delegator`, which
  permits only `TokenReview`/`SubjectAccessReview`.
- On each login OpenBao sends the pod's token to the TokenReview endpoint using
  that credential; the API server answers who the token belongs to (namespace +
  service account).
- ⚠️ This reviewer token is the **one long-lived secret** on the Kubernetes side. It
  exists because OpenBao is outside the cluster and has no identity there.
  (Since k8s 1.24 it needs an explicit Secret; see the comment in `k8s/bao-auth/bao-auth.yaml`.)

### 2. Pods trust OpenBao

Pods verify `https://bao:8200` against the lab CA, published once as a cluster-wide ClusterTrustBundle and mounted
through a `clusterTrustBundle` projected volume (`docs/CLUSTER-TRUST.md`). The laptop uses
a different address (`https://bao.orb.local`, OrbStack's system-trusted HTTPS)
and needs no CA.

### 3. The network path

Pods must reach `bao:8200` and OpenBao must reach the API server; both work only
because they share the `kind` docker network. Recreating the `bao` container
drops the attachment; the scripts re-attach it.

## 🔐 Authorization starts at login, not after it

- Role `app` admits only service accounts in `team-a` and `team-b` and requires
  audience `bao` (the default API-server audience token is rejected).
- On success OpenBao issues a 5-minute token with only the templated `k8s-app`
  policy; the templates resolve to the namespace/service account that
  TokenReview confirmed.

## The `jwt-k8s` variant needs less runtime trust

OpenBao holds the API server's **public signing key** (read from
`/etc/kubernetes/pki/sa.pub` in the kind node and pinned by Terraform) and verifies the token signature itself: no call
to the API server, no reviewer token. Trade-off: if the cluster's signing key
rotates, re-apply Terraform. It is also what exposes the pod name (see
`POLICIES.md`).

## Who authenticates what during setup? (the real bootstrap)

The work is split so each tool has one job (see the diagram in `DIAGRAMS.md`):

- **Kustomize** (`kubectl apply -k k8s`, via your kubeconfig, context `kind-vault-lab`) creates everything on
  the cluster side: namespaces, service accounts, `bao-auth` + its token, the trust bundle, Postgres.
- **Terraform** configures only OpenBao. It uses the OpenBao **root token** from `.secrets/init.json`, created
  by `operator init` on the first `task bao:up`. It creates no cluster objects: read-only
  data sources (`terraform/cluster.tf`, kubeconfig credentials) fetch the cluster CA, the reviewer token and the
  Postgres root password that Kustomize created.
- Order matters: the cluster objects must exist before Terraform, because the reviewer token is created there.
- Anything an agent or human needs beyond that is a named policy, `lab-admin`,
  not the root token.

## 🚧 Production hardening (not done in the lab)

- Revoke the root token after setup; administer via `lab-admin` through
  OIDC/userpass.
- ⚠️ Avoid the long-lived reviewer credential. It lives in OpenBao's config and in Terraform state (the data source
  in `cluster.tf` reads it). Prefer the `jwt` method: it verifies tokens by signature and has no reviewer secret.
  On a real cluster (EKS/GKE/AKS) point it at the cluster's public OIDC issuer (`oidc_discovery_url`), so no key
  is pinned and no secret exists at all; pinning `sa.pub` is only needed on kind. Pod-name policies already use
  this mount. For the `kubernetes` method, a short-lived/rotated reviewer token is the fallback.
- Unseal via KMS/transit instead of a key file; run OpenBao where the same trust
  applies without a shared docker network.
