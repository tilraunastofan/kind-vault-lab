# Terraform manages OpenBao only. Kubernetes objects live in k8s/ (Kustomize); the few cluster-derived values
# below are passed in by scripts/tf.sh so this config has no kubernetes provider.

variable "bao_addr" {
  description = "OpenBao address as seen from this laptop (OrbStack automatic HTTPS, system-trusted)"
  default     = "https://bao.orb.local"
}

# Different vantage points, different addresses: the laptop uses bao.orb.local, pods use bao:8200, and
# bao itself calls the API server by its docker name (the kubeadm cert includes that name as a SAN).
variable "k8s_host_for_bao" {
  description = "API server address as seen from the bao container (kind network)"
  default     = "https://vault-lab-control-plane:6443"
}

# Only these namespaces may authenticate (audit: explicit allow-list, no wildcards). Must match the tenants in k8s/.
variable "onboarded_namespaces" {
  type    = list(string)
  default = ["team-a", "team-b"]
}

variable "k8s_ca_cert" {
  description = "Cluster CA (kube-root-ca.crt), so OpenBao can verify the API server"
  type        = string
}

variable "k8s_reviewer_jwt" {
  description = "Token of SA kube-system/bao-auth (auth-delegator): OpenBao's credential for TokenReview"
  type        = string
  sensitive   = true
}

variable "k8s_sa_pubkey" {
  description = "API server service-account signing public key (PEM), pinned in the jwt-k8s mount"
  type        = string
}

variable "pg_root_password" {
  description = "Postgres root password (generated in k8s/data/pg-root.env); OpenBao's database engine connects with it"
  type        = string
  sensitive   = true
}
