variable "name_prefix" {
  description = "Resource name prefix - passed from root locals"
  type        = string
}

variable "region" {
  description = "AWS region - used to build CloudWatch dashboard"
  type        = string
}

variable "asg_name" {
  description = "Auto Scaling Group name - used for EC2 CPU alarms"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix - used for ALB 5xx error alarms"
  type        = string
}

variable "rds_instance_identifier" {
  description = "RDS instance identifier - used for RDS connection count alarms"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN - alarms send notifications here"
  type        = string
}

variable "dlq_name" {
  description = "for the cloudwatch alarm"
  type        = string
}