# Mock tenants. team-a and team-b are onboarded to OpenBao; team-c is not (negative control).
locals {
  namespaces = ["team-a", "team-b", "team-c"]

  # "<namespace>/<serviceaccount>" => has dynamic DB creds + kv secrets
  apps = {
    "team-a/payments" = { ns = "team-a", sa = "payments" }
    "team-a/frontend" = { ns = "team-a", sa = "frontend" }
    "team-a/ledger"   = { ns = "team-a", sa = "ledger" } # pods ledger-0 / ledger-1 (pod-name demo)
    "team-b/billing"  = { ns = "team-b", sa = "billing" }
    "team-c/rogue"    = { ns = "team-c", sa = "rogue" }
  }

  # Only these namespaces may authenticate (audit: explicit allow-list, no wildcards)
  onboarded_namespaces = ["team-a", "team-b"]
}

resource "kubernetes_namespace_v1" "ns" {
  for_each = toset(local.namespaces)
  metadata { name = each.key }
}

resource "kubernetes_service_account_v1" "app" {
  for_each = local.apps
  metadata {
    name      = each.value.sa
    namespace = kubernetes_namespace_v1.ns[each.value.ns].metadata[0].name
  }
}

# CA that pods use to trust OpenBao (in-cluster address https://bao:8200).
resource "kubernetes_config_map_v1" "bao_ca" {
  for_each = kubernetes_namespace_v1.ns
  metadata {
    name      = "bao-ca"
    namespace = each.value.metadata[0].name
  }
  data = { "ca.crt" = file(pathexpand(var.bao_ca_file)) }
}
