variable "bao_addr" {
  description = "OpenBao address as seen from this laptop (OrbStack automatic HTTPS, system-trusted)"
  default     = "https://bao.orb.local"
}

variable "bao_ca_file" {
  default = "../bao/pki/ca.crt"
}

variable "bao_addr_in_cluster" {
  description = "OpenBao address as seen from pods (bao container is attached to the kind network)"
  default     = "https://bao:8200"
}

# Different vantage points, different addresses: the laptop uses bao.orb.local, pods use bao:8200, and
# bao itself calls the API server by its docker name (the kubeadm cert includes that name as a SAN).
variable "k8s_host_for_bao" {
  description = "API server address as seen from the bao container (kind network)"
  default     = "https://vault-lab-control-plane:6443"
}
