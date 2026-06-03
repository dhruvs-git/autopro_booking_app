output "db_rds_endpoint" {
  description = "RDS endpoint - visible in console for debugging"
  value       = module.database.db_rds_endpoint
}

output "db_secret_name" {
  description = "db-secret-name to check in console"
  value       = module.database.db_secret_name
}

output "alb_dns_name" {
  description = "we will use this to test flask app"
  value       = module.compute.alb_dns_name
}


output "cognito_user_pool_id" {
  description = "Cognito User Pool ID - needed for Flask JWT validation"
  value       = module.auth.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito App Client ID - needed for frontend login"
  value       = module.auth.user_pool_client_id
}

output "redis_endpoint" {
  description = "Redis endpoint - needed for Flask cache configuration"
  value       = module.cache.redis_endpoint
}


output "cloudfront_url" {
  description = "CloudFront distribution URL — this is your app's public address"
  value       = module.frontend.cloudfront_url
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — used to invalidate cache after deployments"
  value       = module.frontend.cloudfront_distribution_id
}

output "frontend_bucket_name" {
  description = "S3 bucket name — upload frontend files here"
  value       = module.frontend.frontend_bucket_name
}