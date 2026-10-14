# ---------- Mock kv-v2 data ----------
# kv paths mirror the policy templates in policies.tf: the *path layout is the access-control model*.
# Change one without the other and tenants lose or gain access.
locals {
  app_secrets = {
    "team-a/payments" = { api_key = "pay-mock-1111", webhook_secret = "whsec-mock-a" }
    "team-a/frontend" = { session_key = "fe-mock-2222" }
    "team-b/billing"  = { api_key = "bill-mock-3333" }
  }
  ns_secrets = {
    "team-a" = { feature_flags = "dark-mode,beta-checkout" }
    "team-b" = { feature_flags = "invoices-v2" }
  }
  pod_secrets = {
    "team-a/ledger-0" = { shard_key = "shard-0-mock" }
    "team-a/ledger-1" = { shard_key = "shard-1-mock" }
  }
}

resource "vault_kv_secret_v2" "app" {
  for_each  = local.app_secrets
  mount     = "secret"
  name      = "apps/${each.key}/config"
  data_json = jsonencode(each.value)
}

resource "vault_kv_secret_v2" "ns" {
  for_each  = local.ns_secrets
  mount     = "secret"
  name      = "namespaces/${each.key}/shared"
  data_json = jsonencode(each.value)
}

resource "vault_kv_secret_v2" "pod" {
  for_each  = local.pod_secrets
  mount     = "secret"
  name      = "pods/${each.key}/config"
  data_json = jsonencode(each.value)
}

# ---------- Postgres (mock "orders" DB, deployed from k8s/data) + dynamic credentials ----------
resource "vault_mount" "database" {
  path = "database"
  type = "database"
}

resource "vault_database_secret_backend_connection" "orders" {
  backend = vault_mount.database.path
  name    = "orders"
  # Connection-level allow-list: even a misconfigured role elsewhere can't mint creds from this connection.
  allowed_roles = [for k, _ in local.app_secrets : replace(k, "/", "-")]
  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@vault-lab-worker:30432/orders?sslmode=disable"
    username       = "postgres"
    password       = data.kubernetes_secret_v1.postgres_root.data["POSTGRES_PASSWORD"]
  }
}

# One DB role per <namespace>-<serviceaccount>; the policy template maps identity -> role name.
resource "vault_database_secret_backend_role" "app" {
  for_each = local.app_secrets
  backend  = vault_mount.database.path
  name     = replace(each.key, "/", "-")
  db_name  = vault_database_secret_backend_connection.orders.name
  # Short-lived on purpose: a leaked credential expires by itself and bao drops the DB role at expiry.
  default_ttl = 300
  max_ttl     = 900
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
  ]
  revocation_statements = [
    "DROP ROLE IF EXISTS \"{{name}}\";",
  ]
}
