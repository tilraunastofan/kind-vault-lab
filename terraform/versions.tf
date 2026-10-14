terraform {
  required_version = ">= 1.6"

  # State lives in HCP Terraform; the workspace uses local execution
  # (created by scripts/tfc-workspace-up.sh).
  cloud {
    organization = "tilraunastofan"
    workspaces {
      name = "kind-vault-lab"
    }
  }

  required_providers {
    vault      = { source = "hashicorp/vault", version = "~> 4.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
    external   = { source = "hashicorp/external", version = "~> 2.3" }
  }
}

# Why the hashicorp/vault provider for OpenBao: OpenBao forked from Vault and kept the API, so it works.
# OpenBao is API compatible with the vault provider. Token comes from VAULT_TOKEN.
provider "vault" {
  address = var.bao_addr
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-vault-lab"
}
