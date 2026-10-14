# Terraform manages OpenBao only. Kubernetes objects live in k8s/ (Kustomize); cluster.tf reads what OpenBao needs.

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
