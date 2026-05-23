variable "project_name" {
  description = "Project name - will use this as prefix on every resource"
  type = string

  validation {
    condition = length(var.project_name) >= 4  && length(var.project_name) <= 15
    error_message = "Project Name must be between 4 to 15 letters"
  }
}

variable "environment" {
  description = "environment : dev, prod or staging"
  type = string

  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, prod or staging"
  }
}

variable "region" {
  description = "The region of deployment"
  type = string
}