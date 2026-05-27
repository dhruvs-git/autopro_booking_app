output "db_rds_endpoint" {
  description = "db-secret-name to check in console"
  value       = module.database.db_rds_endpoint
}

output "db_secret_name" {
  description = "db-secret-name to check in console"
  value       = module.database.db_secret_name
}

output "alb_dns_name" {
  description = "we will use this to test flask app"
  value = module.compute.alb_dns_name
}