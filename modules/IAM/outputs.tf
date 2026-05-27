output "ec2_instance_profile_name" {
  description = "Goes into launch Template"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "ec2_instance_profile_arn" {
  description = "instance profile arn"
  value       = aws_iam_instance_profile.ec2_profile.arn
}

output "ec2_role_arn" {
  description = "EC2 IAM role arn"
  value       = aws_iam_role.ec2_role.arn
}