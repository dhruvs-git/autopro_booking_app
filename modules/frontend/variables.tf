
variable "name_prefix" {
  description = "resource name prefix"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS Name - Cloudfront forwards api calls here"
  type        = string
}

