# Read-only view of the cluster (objects are created by `kubectl apply -k k8s`; no kubernetes_* resources here).
# Order: `task k8s:apply` must run first, or these reads fail at plan time.

data "kubernetes_config_map_v1" "kube_root_ca" {
  metadata {
    name      = "kube-root-ca.crt"
    namespace = "kube-system"
  }
}

# OpenBao's long-lived TokenReview credential (SA bao-auth, created in k8s/bao-auth/).
# Lands in Terraform state: acceptable for the lab; for production prefer the jwt method, which has no such secret
# (docs/TRUST-BOOTSTRAP.md).
data "kubernetes_secret_v1" "bao_auth_token" {
  metadata {
    name      = "bao-auth-token"
    namespace = "kube-system"
  }
}

# Same root password the postgres Deployment uses (k8s/data), so OpenBao's database engine can connect.
data "kubernetes_secret_v1" "postgres_root" {
  metadata {
    name      = "postgres-root"
    namespace = "data"
  }
}

# The API server's SA signing key, pinned in the jwt-k8s mount. OpenBao can't fetch /openid/v1/jwks (it needs
# auth), and kind has no public issuer. Lab-specific: on a real cluster use oidc_discovery_url with the public issuer.
data "external" "sa_pubkey" {
  program = ["bash", "-c", "docker exec vault-lab-control-plane cat /etc/kubernetes/pki/sa.pub | jq -Rs '{pem: .}'"]
}
