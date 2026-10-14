# ---------- Auth method 1: kubernetes (namespace + serviceaccount identity) ----------

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
  tune {
    default_lease_ttl = "10m"
    max_lease_ttl     = "30m"
    # set explicitly: the server reports this default back and the provider otherwise shows a diff on every plan
    token_type = "default-service"
  }
}

resource "vault_kubernetes_auth_backend_config" "this" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.k8s_host_for_bao
  kubernetes_ca_cert = var.k8s_ca_cert
  token_reviewer_jwt = var.k8s_reviewer_jwt
}

# ONE generic role for all apps. Identity is not baked into the role; it is
# resolved at request time by the templated policy below. Onboarding a new
# service = create SA + data, no role/policy change.
resource "vault_kubernetes_auth_backend_role" "app" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "app"
  bound_service_account_names      = ["*"] # any SA, but only in allow-listed namespaces
  bound_service_account_namespaces = var.onboarded_namespaces
  audience                         = "bao" # token must be projected with aud=bao, not the API-server default
  alias_name_source                = "serviceaccount_name"
  token_policies                   = [vault_policy.k8s_app.name]
  token_no_default_policy          = true # `default` grants extras (cubbyhole etc.); auditors prefer explicit grants only
  token_ttl                        = 300
  token_max_ttl                    = 900
  token_type                       = "service"
}

# ---------- Auth method 2: jwt (adds POD NAME / UID identity) ----------
# The kubernetes method cannot see the pod name. Projected SA tokens carry
# kubernetes.io/pod/{name,uid} claims, so we validate them as plain JWTs.

resource "vault_jwt_auth_backend" "k8s_jwt" {
  path         = "jwt-k8s"
  type         = "jwt"
  bound_issuer = "https://kubernetes.default.svc.cluster.local"
  # trimspace: bao stores the PEM without its trailing newline; keeping it would show a diff on every plan
  jwt_validation_pubkeys = [trimspace(var.k8s_sa_pubkey)]
  tune {
    default_lease_ttl = "10m"
    max_lease_ttl     = "30m"
    # set explicitly: the server reports this default back and the provider otherwise shows a diff on every plan
    token_type = "default-service"
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
  # Copy claims into alias metadata: that is what {{identity.entity.aliases.*.metadata.*}} reads in policies.
  claim_mappings = {
    "/kubernetes.io/namespace"           = "namespace"
    "/kubernetes.io/pod/name"            = "pod_name"
    "/kubernetes.io/serviceaccount/name" = "service_account"
  }
  # same namespace allow-list as the kubernetes role (audit: no unscoped logins)
  # Without this any namespace could log in (found by the team-c negative test). The glob type is what
  # makes the comma-separated value act as a list of allowed values.
  bound_claims_type       = "glob"
  bound_claims            = { "/kubernetes.io/namespace" = join(",", var.onboarded_namespaces) }
  token_policies          = [vault_policy.k8s_pod.name]
  token_no_default_policy = true
  token_ttl               = 300
  token_max_ttl           = 900
}
