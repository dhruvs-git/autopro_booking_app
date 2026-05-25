output "vpc_id" {
  description = "The ID of vpc - passed to every module that needs it"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet ids ALB goes here"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "Private app subnets ids ASG and ec2 needs it"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "DB subnets ids RDS and redis needs it"
  value       = aws_subnet.private_db[*].id
}

output "nat_gateway_id" {
  description = "NAT gateway ID"
  value       = aws_nat_gateway.main.id
}
