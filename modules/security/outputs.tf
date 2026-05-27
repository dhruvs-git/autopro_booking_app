output "alb_sg_id" {
  description = "ALB SG ID PASSED TO COMPUTE MODULE"
  value       = aws_security_group.alb.id
}

output "ec2_sg_id" {
  description = "Ec2 Security group ID - Attaching to launch template"
  value       = aws_security_group.ec2.id
}

output "rds_sg_id" {
  description = "RDS security group ID — passed to database module"
  value       = aws_security_group.rds.id
}

output "redis_sg_id" {
  description = "Redis security group ID — passed to cache module"
  value       = aws_security_group.redis.id
}