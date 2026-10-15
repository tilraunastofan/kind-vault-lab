# Per-service-account PKI certificates

Status: **concept, not implemented yet** (backlog item 1 in `IDEAS.md`).

## The idea

A pod logs in to OpenBao with its service-account token (see `POLICIES.md`) and may then request a
certificate **only for its own name**, e.g. `payments.team-a.svc`. A single PKI role with
`allowed_domains_template=true` does this, with domains templated from the login's alias metadata:

```
{{identity.entity.aliases.<acc>.metadata.service_account_name}}.{{identity.entity.aliases.<acc>.metadata.service_account_namespace}}.svc
```

Same pattern as the `k8s-app` policy: identity is resolved from the platform at request time, so onboarding
a service needs no PKI role or policy edit.

## What it gives us

1. **Mutual TLS between services.** A service-account token proves identity to OpenBao and the Kubernetes API only.
   A certificate lets two services prove who they are to *each other*, in both directions.
2. **Authorization by certificate name.** A service can allow callers by the identity in the cert ("only
   `team-a/frontend` may call `/charge`"). Meshes (Istio, Linkerd) do this with SPIFFE-style IDs
   (`spiffe://cluster/ns/team-a/sa/payments`); the cert can carry the same URI SAN, so the identity matches the one OpenBao uses.
3. **No impersonation, enforced by policy.** The CA only signs names derived from the caller's own namespace and
   service account, so `payments` cannot obtain a certificate for `frontend`, even if compromised.
4. **Short-lived and self-expiring.** Minutes-to-hours lifetimes mean no revocation lists and no manual renewal; a
   stolen key dies on its own. Consistent with the 5-minute tokens and DB credentials in this lab.
5. **No shared secrets or API keys** for service-to-service calls. The private key can be generated in the pod and
   never leaves it; only the signing request goes to OpenBao.
6. **One trust root.** Everything chains to the CA OpenBao runs, which can also sign ingress/database certs;
   rotation happens in one place.

## Kubernetes-native alternative: Pod Certificates

Kubernetes 1.37 adds `PodCertificateRequest` + a `podCertificate` projected volume: kubelet makes the key, a signer
controller issues the cert. A signer that forwards to OpenBao's PKI engine would give the same per-identity certs
without the login step; see `CLUSTER-TRUST.md`.

## Compared with the alternatives

- **cert-manager:** also issues certificates, but signs whatever the `Certificate` resource asks for. Here the name
  is bound to the authenticated identity by policy.
- **Service mesh:** gives most of this transparently (mTLS, rotation). The OpenBao approach is more manual (the app
  or a sidecar must request and reload certs) but fits when there is no mesh or OpenBao must be the CA.

## Limits

- The service-account token is still the bootstrap credential: whoever steals it can request that service
  account's certificate until the token expires.
- Services must verify peer certificates and reload on rotation; many do neither out of the box. A certificate
  alone protects nothing without a verifying server.

## Planned test (extends `scripts/smoke-test.sh`)

`team-a/payments` issues `payments.team-a.svc` (200) and is refused `frontend.team-a.svc` (4xx); `team-c/rogue`
cannot log in at all. Needs: a `pki` mount, a root/intermediate CA, one templated role, and policy path `pki/issue/<role>`.
