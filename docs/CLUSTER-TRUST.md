# Cluster-wide trust for OpenBao's CA (ClusterTrustBundle)

Status: **implemented** (`k8s/bao-ca/`, `scripts/k8s-up.sh`, verified by `task smoke`).
Background: Kubernetes v1.37 "Pod Certificates and Cluster Trust Bundles" (blog post, 2026-08-28).

## Problem
OpenBao's TLS cert is signed by a private lab CA that no container image trusts. We used to ship the CA as a
`bao-ca` ConfigMap into every namespace (ConfigMaps are namespaced), generated three times by Kustomize.

## What we use now
One **ClusterTrustBundle** (cluster-scoped, `certificates.k8s.io/v1`) holds the CA. A pod opts in with a
`clusterTrustBundle` projected volume; kubelet resolves and keeps the file up to date:

```yaml
volumes:
  - name: ca
    projected:
      sources:
        - clusterTrustBundle:
            signerName: bao.lab.internal/server-ca
            labelSelector: {matchLabels: {trust: bao}}
            path: ca.crt
```

⭐ **No per-namespace object, nothing to copy when a namespace is added.** The bundle is rendered by `scripts/k8s-up.sh`
(the CA is generated per laptop and gitignored) and applied with the rest of `k8s/`.

## Design choices and findings
- 🔐 **Signer-linked bundle, selected by `signerName` + labels.** Creating or changing a bundle that sets `signerName`
  requires the `attest` verb on that signer, so the trust anchor is guarded by RBAC. The object name must be the
  signer name with `/` turned into `:` (`bao.lab.internal:server-ca:v1`); a rotation is a second `:v2` object.
- 🐛 **The CA must have `basicConstraints CA:TRUE`.** The API server rejected our old lab CA ("entry 0 does not have
  the CA bit set"). `scripts/bao-up.sh` now generates a proper CA (and a server cert with `serverAuth`); that was
  a genuine bug the old ConfigMap approach hid.
- ⚠️ **Still opt-in per pod.** This removes the per-namespace *object*, not the per-pod *mount*. Nothing injects the
  CA into every container's system trust store. For that, use trust-manager, bake the CA into base images, or have
  tooling (Vault Agent, CSI, ESO) carry it.
- **Kubelet normalises the PEM** (strips comments, deduplicates, arbitrary order) and updates the file when the
  bundle changes; apps must reload via inotify or polling.
- ⚠️ **Docs mismatch on 1.37.0:** `kubectl explain` still labels the projection "Alpha, gated by
  ClusterTrustBundleProjection", while the blog and the official CSR docs page say Stable since v1.37. It works on this kind cluster (v1.37.0) without any
  feature-gate change. Treat the explain text as stale.
- 💡 **The cluster publishes its own bundle too:** `kubernetes.io:kube-apiserver-serving:<hash>`
  (signer `kubernetes.io/kube-apiserver-serving`). Pods can select it the same way to trust the API server,
  instead of reading `kube-root-ca.crt`.

## 💡 Pod Certificates (the other half of the post), and how it fits OpenBao
Pod Certificates (`PodCertificateRequest`, `podCertificate` projected volume) give each pod a kubelet-generated
private key and an X.509 certificate from a **signer controller**; core Kubernetes ships no signer yet (the post
uses the toy "Tinycert"). The `PodCertificateRequest` API is served by this cluster.
Related ideas, not built (see `PKI.md`, `IDEAS.md`):
- a signer controller that forwards requests to OpenBao's PKI engine, so OpenBao is the CA behind Kubernetes-native
  pod certs (no login step, key never leaves the node/pod, node-restriction checks done by kube-apiserver);
- publish that signer's CA as a ClusterTrustBundle for mTLS peers, the same mechanism as above.
