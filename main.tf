module "networking" {
  source = "./modules/networking"

  name_prefix = local.name_prefix
  vpc_cidr = var.vpc_cidr
  availability_zones = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs = var.private_db_subnet_cidrs
}