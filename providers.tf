provider "aws" {
  region  = var.region
  profile = "terralearn"

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "terralearn"

  default_tags {
    tags = local.common_tags
  }
}