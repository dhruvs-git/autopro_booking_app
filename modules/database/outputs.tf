output "db_secret_arn" {
  description = "Secrets Manager ARN — passed to compute module so EC2 knows where to fetch credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_secret_name" {
  description = "Secrets Manager secret name"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "db_rds_endpoint" {
  description = "rds-endpoint for root output"
  value       = aws_db_instance.main.address
}

output "rds_instance_identifier" {
  description = "RDS instance identifier — used for CloudWatch metric dimensions"
  value       = aws_db_instance.main.id
}