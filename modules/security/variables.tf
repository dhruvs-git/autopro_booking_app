variable "name_prefix" {
  description = "resource name prefix - passed from root locals"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID — security groups must live inside a VPC"
  type        = string
}