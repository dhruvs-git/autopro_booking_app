output "user_pool_id" {
  description = "Cognito User Pool ID — used by Flask to validate JWT tokens"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  description = "Cognito App Client ID — used by frontend to authenticate users"
  value       = aws_cognito_user_pool_client.main.id
}