variable "name_prefix" {
  description = "Resource name prefix -passed from root locals"
  type        = string
}

variable "private_db_subnet_ids" {
  description = "Private DB subnet IDs -Redis lives here alongside RDS"
  type        = list(string)
}

variable "redis_sg_id" {
  description = "Redis security group ID -from security module"
  type        = string
}

variable "redis_node_type" {
  description = "Redis node type -cache.t3.micro is Free Tier eligible"
  type        = string

  validation {
    condition     = can(regex("^cache\\.", var.redis_node_type))
    error_message = "Must be a valid ElastiCache node type starting with cache."
  }
}