# Policy tricks to demo next

Backlog of ideas that build on the existing identity plumbing (see `POLICIES.md`). None are implemented yet.
Each item lists the idea, how to test it with the existing matrix (`scripts/smoke-test.sh`), and caveats.

Suggested order: 1, 2, 4, then 3 if "one team across several namespaces" matters.

## Best candidates

### 1. One PKI role, certificates only for your own name
A single PKI role with `allowed_domains_template=true`, with domains such as
`{{identity.entity.aliases.<acc>.metadata.service_account_name}}.{{identity.entity.aliases.<acc>.metadata.service_account_namespace}}.svc`.
Any onboarded service account can issue mTLS certs for its own service DNS name only. Same "no policy edit on onboarding" idea as
`k8s-app`, applied to certificates.

- Background: see `PKI.md`.
- Test: `team-a/payments` can issue `payments.team-a.svc` (200) and is refused `frontend.team-a.svc` (4xx).
- Needs: a `pki` mount, a root/intermediate CA, one role, one policy path `pki/issue/<role>`.

### 2. Per-identity kill switch
Disable a single entity (`identity/entity/id/<id>`, `disabled=true`) to lock out one service account immediately,
including its existing tokens, while every other workload keeps working. Shows incident response and revocation scope.

- Test: pod reads a secret (OK), entity disabled, same pod is denied within seconds. Visible as OK -> DENY in `task audit`.
- Caveat: the alias is per service account (`alias_name_source = serviceaccount_name`), so disabling affects every pod of that SA.

### 3. Policy driven by metadata and groups, not names
Put `team=<name>` on the entity (or an internal group) and write policy against `{{identity.entity.metadata.team}}`.
Several namespaces can share one team's secrets without listing service accounts; a reorg becomes a metadata change.

- Test: `team-a/payments` and `team-b/billing` both tagged `team=finance` read `secret/data/teams/finance/*`; `team-a/frontend` cannot.
- Caveat: entity metadata is only as trustworthy as whoever can write to `identity/*`; keep that in `lab-admin` only.

### 4. Constrain the token, not just the paths
- `token_bound_cidrs` on the auth role so a stolen token is useless off-cluster. Test: replay a pod's token from the Mac and expect a denial.
  Caveat: bao sees the node IP (kube-proxy SNAT), not the pod IP, so bind to the kind node range.
- `min_wrapping_ttl` / `max_wrapping_ttl` in policy to force response wrapping for sensitive reads (secret-zero handoff).
- `allowed_parameters` / `denied_parameters` / `required_parameters` in policy to limit what a client may ask for (e.g. cap a cert TTL).

## Worth considering

- **Transit with identity-named keys:** `transit/encrypt/{{ns}}-{{sa}}`; split encrypt and decrypt across identities (producer vs consumer).
- **Namespaces for multi-tenancy:** a namespace per team with a delegated admin who manages only their own policies.
  Believed to be in OpenBao since ~2.3; verify against 2.7 before building.
- **Detection:** a `task audit:denied` filter plus a test that a burst of DENYs stands out.
- **Static DB credentials with rotation** and `database/rotate-root/orders` (production TODO from `POLICIES.md`).

## Not available in OpenBao
Sentinel/EGP policies and control groups (approval-gated reads) are Vault Enterprise features and cannot be demoed here.
Closest substitutes: the kill switch (2) and wrapping requirements (4).
