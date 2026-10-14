variable "bao_addr" {
  description = "OpenBao address as seen from this laptop (OrbStack)"
  default     = "https://bao.orb.local:8200"
}

variable "bao_ca_file" {
  default = "~/bao/pki/ca.crt"
}

variable "bao_addr_in_cluster" {
  description = "OpenBao address as seen from pods (bao container is attached to the kind network)"
  default     = "https://bao:8200"
}

variable "k8s_host_for_bao" {
  description = "API server address as seen from the bao container (kind network)"
  default     = "https://vault-lab-control-plane:6443"
}
