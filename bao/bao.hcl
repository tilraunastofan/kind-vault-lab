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

api_addr     = "https://bao.orb.local:8200"
cluster_addr = "https://bao.orb.local:8201"
