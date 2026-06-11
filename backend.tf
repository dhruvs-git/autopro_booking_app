terraform {
  backend "s3" {
    bucket       = "autoserve-app-terraform-state"
    key          = "dev/terraform.tfstate"
    region       = "ca-central-1"
    encrypt      = true
    use_lockfile = true # we dont need DynamoDB now for state locking
  }
}