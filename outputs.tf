output "db_rds_endpoint" {
  description = "db-secret-name to check in console"
  value = module.database.db_rds_endpoint
}

output "db_secret_name" {
  description = "db-secret-name to check in console"
  value = module.database.db_secret_name
}