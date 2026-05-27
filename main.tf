module "networking" {
  source = "./modules/networking"

  name_prefix = local.name_prefix
  vpc_cidr = var.vpc_cidr
  availability_zones = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs = var.private_db_subnet_cidrs
}


module "security" {
  source = "./modules/security"

  name_prefix = local.name_prefix
  vpc_id = module.networking.vpc_id
}

# Gets you the account ID
data "aws_caller_identity" "current"{}

module "IAM" {
  source = "./modules/IAM"

  name_prefix = local.name_prefix
  project_name = var.project_name
  environment = var.environment
  region = var.region
  aws_account_id = data.aws_caller_identity.current.account_id
}


module "database" {
  source = "./modules/database"

  name_prefix = local.name_prefix
  secret_path = local.secret_path
  db_name = var.db_name
  db_username = var.db_username
  db_instance_class = var.db_instance_class
  private_db_subnet_ids = module.networking.private_db_subnet_ids
  rds_sg_id = module.security.rds_sg_id
}