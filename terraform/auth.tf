# ---------- Auth method 1: kubernetes (namespace + serviceaccount identity) ----------

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
  tune {
    default_lease_ttl = "10m"
    max_lease_ttl     = "30m"
  }
}

resource "vault_kubernetes_auth_backend_config" "this" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.k8s_host_for_bao
  kubernetes_ca_cert = data.kubernetes_config_map_v1.kube_root_ca.data["ca.crt"]
  token_reviewer_jwt = kubernetes_secret_v1.bao_auth_token.data["token"]
}

# ONE generic role for all apps. Identity is not baked into the role; it is
# resolved at request time by the templated policy below. Onboarding a new
# service = create SA + data, no role/policy change.
resource "vault_kubernetes_auth_backend_role" "app" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "app"
  bound_service_account_names      = ["*"] # any SA, but only in allow-listed namespaces
  bound_service_account_namespaces = local.onboarded_namespaces
  audience                         = "bao" # token must be projected with aud=bao, not the API-server default
  alias_name_source                = "serviceaccount_name"
  token_policies                   = [vault_policy.k8s_app.name]
  token_no_default_policy          = true # drop the broad `default` policy
  token_ttl                        = 300
  token_max_ttl                    = 900
  token_type                       = "service"
}

# ---------- Auth method 2: jwt (adds POD NAME / UID identity) ----------
# The kubernetes method cannot see the pod name. Projected SA tokens carry
# kubernetes.io/pod/{name,uid} claims, so we validate them as plain JWTs.

data "external" "sa_pubkey" {
  program = ["bash", "-c", "docker exec vault-lab-control-plane cat /etc/kubernetes/pki/sa.pub | jq -Rs '{pem: .}'"]
}

resource "vault_jwt_auth_backend" "k8s_jwt" {
  path                   = "jwt-k8s"
  type                   = "jwt"
  bound_issuer           = "https://kubernetes.default.svc.cluster.local"
  jwt_validation_pubkeys = [data.external.sa_pubkey.result.pem]
  tune {
    default_lease_ttl = "10m"
    max_lease_ttl     = "30m"
  }
}

resource "vault_jwt_auth_backend_role" "pod" {
  backend         = vault_jwt_auth_backend.k8s_jwt.path
  role_name       = "pod"
  role_type       = "jwt"
  bound_audiences = ["bao"]
  # one entity per POD UID -> pod name is reliable in alias metadata
  user_claim              = "/kubernetes.io/pod/uid"
  user_claim_json_pointer = true
  claim_mappings = {
    "/kubernetes.io/namespace"           = "namespace"
    "/kubernetes.io/pod/name"            = "pod_name"
    "/kubernetes.io/serviceaccount/name" = "service_account"
  }
  # same namespace allow-list as the kubernetes role (audit: no unscoped logins)
  bound_claims_type       = "glob"
  bound_claims            = { "/kubernetes.io/namespace" = join(",", local.onboarded_namespaces) }
  token_policies          = [vault_policy.k8s_pod.name]
  token_no_default_policy = true
  token_ttl               = 300
  token_max_ttl           = 900
}
