locals {
  k8s_acc = vault_auth_backend.kubernetes.accessor
  jwt_acc = vault_jwt_auth_backend.k8s_jwt.accessor
  # template fragments (resolved by OpenBao per request from the login's entity alias)
  k8s_ns  = "{{identity.entity.aliases.${local.k8s_acc}.metadata.service_account_namespace}}"
  k8s_sa  = "{{identity.entity.aliases.${local.k8s_acc}.metadata.service_account_name}}"
  jwt_ns  = "{{identity.entity.aliases.${local.jwt_acc}.metadata.namespace}}"
  jwt_pod = "{{identity.entity.aliases.${local.jwt_acc}.metadata.pod_name}}"
}

# Audit-friendly properties:
#  - read-only, least privilege, every path fully anchored (no globs on the identity segments)
#  - no sys/*, no list on parent paths, no sudo, no `default` policy
#  - identity comes from the platform (SA token), never from client-supplied input
resource "vault_policy" "k8s_app" {
  name   = "k8s-app"
  policy = <<-EOT
    # service-private secrets: secret/apps/<namespace>/<serviceaccount>/*
    path "secret/data/apps/${local.k8s_ns}/${local.k8s_sa}/*" {
      capabilities = ["read"]
    }

    # namespace-shared secrets: secret/namespaces/<namespace>/*
    path "secret/data/namespaces/${local.k8s_ns}/*" {
      capabilities = ["read"]
    }

    # dynamic database credentials, one DB role per <namespace>-<serviceaccount>
    path "database/creds/${local.k8s_ns}-${local.k8s_sa}" {
      capabilities = ["read"]
    }

    # let the workload inspect/renew/revoke ITS OWN token only
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
    path "auth/token/revoke-self" {
      capabilities = ["update"]
    }
  EOT
}

resource "vault_policy" "k8s_pod" {
  name   = "k8s-pod"
  policy = <<-EOT
    # per-pod secrets: secret/pods/<namespace>/<pod-name>/*
    path "secret/data/pods/${local.jwt_ns}/${local.jwt_pod}/*" {
      capabilities = ["read"]
    }
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }
    path "auth/token/revoke-self" {
      capabilities = ["update"]
    }
  EOT
}

# Humans/automation that administer this lab get a named policy instead of root.
resource "vault_policy" "lab_admin" {
  name   = "lab-admin"
  policy = <<-EOT
    path "secret/*"   { capabilities = ["create","read","update","delete","list"] }
    path "database/*" { capabilities = ["create","read","update","delete","list"] }
    path "auth/*"     { capabilities = ["create","read","update","delete","list","sudo"] }
    path "sys/auth/*"     { capabilities = ["create","read","update","delete","sudo"] }
    path "sys/policies/*" { capabilities = ["create","read","update","delete","list"] }
    path "sys/mounts/*"   { capabilities = ["create","read","update","delete"] }
    path "sys/audit*"     { capabilities = ["read","list","sudo"] }
    path "identity/*"     { capabilities = ["create","read","update","delete","list"] }
  EOT
}
