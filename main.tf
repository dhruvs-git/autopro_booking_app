module "networking" {
  source = "./modules/networking"

  name_prefix              = local.name_prefix
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
}


module "security" {
  source = "./modules/security"

  name_prefix = local.name_prefix
  vpc_id      = module.networking.vpc_id
}

# Gets you the account ID
data "aws_caller_identity" "current" {}

module "IAM" {
  source = "./modules/IAM"

  name_prefix    = local.name_prefix
  project_name   = var.project_name
  environment    = var.environment
  region         = var.region
  aws_account_id = data.aws_caller_identity.current.account_id
}


module "database" {
  source = "./modules/database"

  name_prefix           = local.name_prefix
  secret_path           = local.secret_path
  db_name               = var.db_name
  db_username           = var.db_username
  db_instance_class     = var.db_instance_class
  private_db_subnet_ids = module.networking.private_db_subnet_ids
  rds_sg_id             = module.security.rds_sg_id
}


module "compute" {
  source = "./modules/compute"

  name_prefix               = local.name_prefix
  region                    = var.region
  ec2_instance_type         = var.ec2_instance_type
  vpc_id                    = module.networking.vpc_id
  public_subnet_ids         = module.networking.public_subnet_ids
  private_app_subnet_ids    = module.networking.private_app_subnet_ids
  ec2_sg_id                 = module.security.ec2_sg_id
  alb_sg_id                 = module.security.alb_sg_id
  ec2_instance_profile_name = module.IAM.ec2_instance_profile_name
  db_secret_arn             = module.database.db_secret_arn
  redis_endpoint            = module.cache.redis_endpoint
  cognito_user_pool_id      = module.auth.user_pool_id
  cognito_client_id         = module.auth.user_pool_client_id
  sns_topic_arn = module.messaging.sns_topic_arn
  sqs_queue_url = module.messaging.sqs_queue_url
}



#cognito
module "auth" {
  source = "./modules/auth"

  name_prefix = local.name_prefix
  admin_email = var.admin_email
}


#cache

module "cache" {
  source = "./modules/cache"

  name_prefix           = local.name_prefix
  private_db_subnet_ids = module.networking.private_db_subnet_ids
  redis_sg_id           = module.security.redis_sg_id
  redis_node_type       = var.redis_node_type

}


module "frontend" {
  source = "./modules/frontend"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix  = local.name_prefix
  alb_dns_name = module.compute.alb_dns_name
}


module "messaging"{
  source = "./modules/messaging"

  name_prefix = local.name_prefix
  admin_email = var.admin_email
}

