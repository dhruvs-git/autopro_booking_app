variable "name_prefix" {
  description = "resource name prefix - passed from root locals"
  type        = string
}

variable "region" {
  description = "AWS region — used to build ARNs in IAM policy statements"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID — used to build ARNs in IAM policy statements"
  type        = string
}

variable "project_name" {
  description = "Project name — used to scope permissions to this project only"
  type        = string
}

variable "environment" {
  description = "Environment — used to scope permissions to this environment only"
  type        = string
}