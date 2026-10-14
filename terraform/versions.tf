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
    vault = { source = "hashicorp/vault", version = "~> 4.0" }
  }
}

# Why the hashicorp/vault provider for OpenBao: OpenBao forked from Vault and kept the API, so it works.
# OpenBao is API compatible with the vault provider. Token comes from VAULT_TOKEN.
provider "vault" {
  address = var.bao_addr
}
