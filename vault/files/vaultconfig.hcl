storage "postgresql" {
  connection_url = "postgres://username:password@localhost:5432/database_name"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

