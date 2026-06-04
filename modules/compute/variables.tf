variable "name_prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "region" {
  description = "AWS region - injected into user data script"
  type        = string
}

variable "ec2_instance_type" {
  description = "EC2 instance type - t2.micro is Free Tier eligible"
  type        = string

  validation {
    condition     = contains(["t2.micro", "t3.micro", "t3.small"], var.ec2_instance_type)
    error_message = "Use t2.micro or t3.micro to stay within Free Tier."
  }
}

variable "public_subnet_ids" {
  description = "ALB Needs this"
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "EC2/ASG lives here"
  type        = list(string)
}


variable "ec2_sg_id" {
  description = "sg for ec2"
  type        = string
}

variable "alb_sg_id" {
  description = "sg for alb"
  type        = string
}

variable "ec2_instance_profile_name" {
  description = "IAM instance profile for template"
  type        = string
}

variable "db_secret_arn" {
  description = "secret manager DB fetches credentials from here at startup"
  type        = string
}

variable "vpc_id" {
  description = "The vpc ID"
  type        = string
}

variable "redis_endpoint" {
  description = "Redis endpoint - from cache module"
  type        = string
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID - from auth module"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito App Client ID - from auth module"
  type        = string
}

variable "sqs_queue_url" {
  description = "SQS queue URL - Flask sends booking events here"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN - worker publishes notifications here"
  type        = string
}