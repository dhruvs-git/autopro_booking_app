variable "name_prefix" {
  description = "Resource name prefix - passed from root locals"
  type        = string
}

variable "admin_email" {
  description = "Email to receive SNS notifications - must confirm subscription"
  type        = string
}
