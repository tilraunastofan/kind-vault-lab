# Plumbing shared by every auth method: token reviewer, CA, kube-root CA data.

resource "kubernetes_service_account_v1" "bao_auth" {
  metadata {
    name      = "bao-auth"
    namespace = "kube-system"
  }
}

# Why an explicit Secret: since k8s 1.24 ServiceAccounts get no long-lived token automatically. Bao calls
# TokenReview outside the cluster and so needs a durable credential; this is that one deliberate exception.
resource "kubernetes_secret_v1" "bao_auth_token" {
  metadata {
    name        = "bao-auth-token"
    namespace   = "kube-system"
    annotations = { "kubernetes.io/service-account.name" = kubernetes_service_account_v1.bao_auth.metadata[0].name }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

# system:auth-delegator = permission to call TokenReview/SubjectAccessReview, nothing else.
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

data "kubernetes_config_map_v1" "kube_root_ca" {
  metadata {
    name      = "kube-root-ca.crt"
    namespace = "kube-system"
  }
}
