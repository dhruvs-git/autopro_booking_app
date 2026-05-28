variable "name_prefix" {
  description = "Resource name prefix - passed from root locals"
  type        = string
}

variable "admin_email" {
  description = "Email address for the admin user - Cognito sends verification here"
  type        = string
}