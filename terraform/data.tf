# ---------- Mock kv-v2 data ----------
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

# ---------- Postgres (mock "orders" DB) + dynamic credentials ----------
resource "random_password" "pg_root" {
  length  = 24
  special = false
}

resource "kubernetes_namespace_v1" "data" {
  metadata { name = "data" }
}

resource "kubernetes_deployment_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.data.metadata[0].name
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "postgres" } }
    template {
      metadata { labels = { app = "postgres" } }
      spec {
        container {
          name  = "postgres"
          image = "postgres:16-alpine"
          env {
            name  = "POSTGRES_PASSWORD"
            value = random_password.pg_root.result
          }
          env {
            name  = "POSTGRES_DB"
            value = "orders"
          }
          port { container_port = 5432 }
          readiness_probe {
            exec { command = ["pg_isready", "-U", "postgres"] }
            initial_delay_seconds = 5
            period_seconds        = 3
          }
          resources {
            limits   = { memory = "256Mi" }
            requests = { memory = "128Mi", cpu = "50m" }
          }
        }
      }
    }
  }
}

# NodePort so the bao container (on the kind docker network) can reach it at vault-lab-worker:30432
resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.data.metadata[0].name
  }
  spec {
    type     = "NodePort"
    selector = { app = "postgres" }
    port {
      port        = 5432
      node_port   = 30432
      target_port = 5432
    }
  }
}

resource "vault_mount" "database" {
  path = "database"
  type = "database"
}

resource "vault_database_secret_backend_connection" "orders" {
  backend       = vault_mount.database.path
  name          = "orders"
  allowed_roles = [for k, _ in local.app_secrets : replace(k, "/", "-")]
  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@vault-lab-worker:30432/orders?sslmode=disable"
    username       = "postgres"
    password       = random_password.pg_root.result
  }
  depends_on = [kubernetes_deployment_v1.postgres, kubernetes_service_v1.postgres]
}

# One DB role per <namespace>-<serviceaccount>; the policy template maps identity -> role name.
resource "vault_database_secret_backend_role" "app" {
  for_each    = local.app_secrets
  backend     = vault_mount.database.path
  name        = replace(each.key, "/", "-")
  db_name     = vault_database_secret_backend_connection.orders.name
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
