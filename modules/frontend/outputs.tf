output "cloudfront_url" {
  description = "CloudFront distribution URL — this is your app's public address"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — used to invalidate cache after deployments"
  value       = aws_cloudfront_distribution.main.id
}

output "frontend_bucket_name" {
  description = "S3 bucket name — upload frontend files here"
  value       = aws_s3_bucket.frontend.bucket
}