ui = true

storage "raft" {
  path    = "/openbao/file"
  node_id = "bao-lab"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/openbao/tls/bao.crt"
  tls_key_file  = "/openbao/tls/bao.key"
}

api_addr     = "https://bao.orb.local"
cluster_addr = "https://bao.orb.local:8201"

# Audit devices are declarative in OpenBao (cannot be enabled via API).
# Every request/response is logged; secret values are HMAC'd.
audit "file" "file" {
  description = "lab audit log"
  options {
    file_path = "/openbao/file/audit.log"
  }
}
