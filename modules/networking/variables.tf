/*variable "project_name" {
  description = "Prefix"
  type = string
}

variable "environment" {
  description = "what is the environment"
  type = string
}*/

variable "name_prefix" {
  description = "resource name prefix - passed from root locals"
  type        = string
}

variable "vpc_cidr" {
  description = "The ID of the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Enter a valid CIDR block"
  }
}

variable "availability_zones" {
  description = "List of AZ to deploy into"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "cidr block for public subnets"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "public_subnet_cidrs and availability_zones must have the same number of entries"
  }
}

variable "private_app_subnet_cidrs" {
  description = "cidr block for app"
  type        = list(string)

  validation {
    condition     = length(var.private_app_subnet_cidrs) == length(var.availability_zones)
    error_message = "private_app_subnet_cidrs and availability_zones must have the same number of entries"
  }
}

variable "private_db_subnet_cidrs" {
  description = "cidr block for the db"
  type        = list(string)

  validation {
    condition     = length(var.private_db_subnet_cidrs) == length(var.availability_zones)
    error_message = "private_db_subnet_cidrs and availability_zones must have the same number of entries"
  }
}