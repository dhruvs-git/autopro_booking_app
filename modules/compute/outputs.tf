output "alb_dns_name" {
  description = "ALB public DNS - use this to test Flask in browser"
  value       = aws_lb.main.dns_name
}

output "asg_name" {
  description = "ASG name - used by GitHub Actions to trigger instance refresh" 
  value       = aws_autoscaling_group.main.name
}