# Projected volumes

A **projected volume** is a Kubernetes volume type that combines several sources into **one directory** inside the
container. "Projected" because the kubelet projects the data into the pod's filesystem as files; the pod does not
fetch it. The lab uses them for the two things a pod needs to talk to OpenBao: a login token and a CA.

## What can be projected

| Source | What the pod gets |
|---|---|
| `serviceAccountToken` | a token minted for this pod, with a chosen audience and lifetime |
| `configMap` / `secret` | selected keys, written as files |
| `downwardAPI` | pod metadata (name, namespace, labels) |
| `clusterTrustBundle` | CA certificates from a cluster-wide bundle (see `CLUSTER-TRUST.md`) |
| `podCertificate` | a kubelet-generated key and certificate for the pod (new in 1.37, needs a signer) |

## How the lab uses them (`scripts/smoke-test.sh`)

```yaml
volumes:
  - name: tok                      # login credential for OpenBao
    projected:
      sources:
        - serviceAccountToken: {audience: bao, path: token, expirationSeconds: 600}
  - name: ca                       # trust for https://bao:8200
    projected:
      sources:
        - clusterTrustBundle:
            signerName: bao.lab.internal/server-ca
            labelSelector: {matchLabels: {trust: bao}}
            path: ca.crt
```

- The token is valid only for OpenBao (`aud=bao`) for 10 minutes. It replaces the default API-server token,
  which the `app` role and the `jwt-k8s` role deliberately reject.
- The CA file comes from one cluster-wide ClusterTrustBundle instead of a ConfigMap per namespace.
- The pod sets `automountServiceAccountToken: false`, so the default token is not mounted at all and a test
  cannot pass by accident with the wrong credential.

## Properties that matter

- **Kubelet creates and refreshes the files.** Tokens are rotated before they expire; trust bundles update when
  the bundle changes. The application only has to re-read the file (inotify or polling).
- **Sources can be mixed.** One projected volume can hold a token, a CA and a ConfigMap key, each at its own path.
- **Tokens are scoped.** They are bound to the pod (invalid once it is deleted) and carry the audience requested,
  so a token stolen from one pod is useless against a service that expects a different audience.
- **Audience is what makes this auditable.** OpenBao checks `aud=bao`; the cluster's default token cannot be
  replayed against it (`POLICIES.md`, `TRUST-BOOTSTRAP.md`).

## Why this removes "secret zero"

The token is created by the platform for a pod that exists; nobody generates, ships or stores it. That is why
OpenBao's `kubernetes` and `jwt` logins need no pre-shared secret (`TRUST-BOOTSTRAP.md`).
