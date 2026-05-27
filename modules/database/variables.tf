variable "name_prefix" {
  description = "resource name prefix - passed from root locals"
  type        = string
}

variable "secret_path" {
  description = "Secrets Manager path prefix -e.g. autoserve/dev"
  type        = string
}

variable "db_name" {
  description = "Database name to create inside RDS"
  type        = string
}

variable "db_username" {
  description = "Master username for RDS MySQL"
  type        = string

  validation {
    condition     = !contains(["admin", "root", "master"], var.db_username)
    error_message = "Cannot use reserved usernames: admin, root, master."
  }
}

variable "db_instance_class" {
  description = "RDS instance type -db.t3.micro is Free Tier eligible"
  type        = string
}

variable "private_db_subnet_ids" {
  description = "Private DB subnet IDs -from networking module"
  type        = list(string)
}

variable "rds_sg_id" {
  description = "RDS security group ID -from security module"
  type        = string
}
