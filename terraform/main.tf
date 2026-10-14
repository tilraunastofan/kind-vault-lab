locals {
  ns = "demo"
}

# ---------- Kubernetes side ----------

resource "kubernetes_namespace_v1" "demo" {
  metadata { name = local.ns }
}

# Token reviewer: OpenBao calls TokenReview with this SA's token.
resource "kubernetes_service_account_v1" "bao_auth" {
  metadata {
    name      = "bao-auth"
    namespace = "kube-system"
  }
}

resource "kubernetes_secret_v1" "bao_auth_token" {
  metadata {
    name        = "bao-auth-token"
    namespace   = "kube-system"
    annotations = { "kubernetes.io/service-account.name" = kubernetes_service_account_v1.bao_auth.metadata[0].name }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

resource "kubernetes_cluster_role_binding_v1" "bao_auth" {
  metadata { name = "bao-auth-delegator" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.bao_auth.metadata[0].name
    namespace = "kube-system"
  }
}

resource "kubernetes_service_account_v1" "demo_app" {
  metadata {
    name      = "demo-app"
    namespace = kubernetes_namespace_v1.demo.metadata[0].name
  }
}

# CA that pods use to trust OpenBao.
resource "kubernetes_config_map_v1" "bao_ca" {
  metadata {
    name      = "bao-ca"
    namespace = kubernetes_namespace_v1.demo.metadata[0].name
  }
  data = { "ca.crt" = file(pathexpand(var.bao_ca_file)) }
}

data "kubernetes_config_map_v1" "kube_root_ca" {
  metadata {
    name      = "kube-root-ca.crt"
    namespace = "kube-system"
  }
}

# ---------- OpenBao side ----------

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "this" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.k8s_host_for_bao
  kubernetes_ca_cert = data.kubernetes_config_map_v1.kube_root_ca.data["ca.crt"]
  token_reviewer_jwt = kubernetes_secret_v1.bao_auth_token.data["token"]
}

resource "vault_policy" "demo_app" {
  name   = "demo-app"
  policy = <<-EOT
    path "secret/data/demo/*" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "demo_app" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "demo-app"
  bound_service_account_names      = [kubernetes_service_account_v1.demo_app.metadata[0].name]
  bound_service_account_namespaces = [local.ns]
  token_policies                   = [vault_policy.demo_app.name]
  token_ttl                        = 600
}

# kv-v2 mount "secret/" is created by ~/bao/scripts/bootstrap.sh
resource "vault_kv_secret_v2" "demo" {
  mount     = "secret"
  name      = "demo/config"
  data_json = jsonencode({ greeting = "hello from openbao", env = "kind-vault-lab" })
}
