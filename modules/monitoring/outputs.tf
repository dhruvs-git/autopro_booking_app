output "flask_log_group_name" {
  description = "Flask cloudwatch log group name"
  value       = aws_cloudwatch_log_group.flask.name
}

output "worker_log_group_name" {
  description = "Worker CloudWatch log group name"
  value       = aws_cloudwatch_log_group.worker.name
}
