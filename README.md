# kind-vault-lab

This is a new `kind` lab that runs on my laptop (16GB RAM). The purpose of this lab is to
test out and experiment with Kubernetes <-> OpenBao setups and configs.

## Environment and credentials

dev sandbox only, agent handling of tokens and credentials is pre-approved

Save all credentials that are generated in `./CREDENTIALS.md` for easy lab navigation

## Lab stack

Lab stack comprises of a few things:

- HCP Terraform Cloud: https://app.terraform.io/app/tilraunastofan/workspaces 
  Claude can use the environment variable "TERRAFORM_TOKEN" to connect to HCP Terraform, this is
  our main "deployment" pipeline for Kubernetes changes and OpenBao changes.

- `kind` to spin up the clusters

- OrbStack (Docker drop-in replacement) for running additional containers: "bao" container is already running,
  we can replace that if needed, for example if credentials need to be re-generated

- Lab should be idempotent, we should be able to bootstrap the whole lab from zero on a new laptop easily

- `task` and `./Taskfile.yaml` is used to run commands and to maintain the lab

- Sibiling labs that can be used as examples: /Users/jakob/Developer/kind-lab-argo-kargo-tekton

- Lab is stored in a private GitHub repo: <https://github.com/tilraunastofan/kind-vault-lab>
