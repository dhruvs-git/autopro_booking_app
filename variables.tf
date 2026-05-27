variable "project_name" {
  description = "Project name - will use this as prefix on every resource"
  type        = string

  validation {
    condition     = length(var.project_name) >= 4 && length(var.project_name) <= 15
    error_message = "Project Name must be between 4 to 15 letters"
  }
}

variable "environment" {
  description = "environment : dev, prod or staging"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, prod or staging"
  }
}

variable "region" {
  description = "The region of deployment"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for vpc"
  type        = string
}

variable "availability_zones" {
  description = "List of AZs"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "cidr blocks for public subnets"
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "cidr blocks for private app subnets - EC2 lives here"
  type        = list(string)
}

variable "private_db_subnet_cidrs" {
  description = "cidr blocks for private db subnets RDS and Redis lives here"
  type        = list(string)
}

variable "db_name" {
  description = "Database name to create inside RDS"
  type        = string
}

variable "db_username" {
  description = "Master username for RDS MySQL"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance type - db.t3.micro is Free Tier eligible"
  type        = string
}

variable "ec2_instance_type" {
  description = "Type of EC2 instance"
  type        = string
}