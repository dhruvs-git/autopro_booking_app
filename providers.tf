provider "aws" {
  region  = var.region
  profile = "terralearn"

  default_tags {
    tags = local.common_tags
  }
}