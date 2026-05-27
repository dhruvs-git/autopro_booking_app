project_name = "autoserve"
environment = "dev"
region = "ca-central-1"

vpc_cidr                 = "10.0.0.0/16"
availability_zones       = ["ca-central-1a", "ca-central-1b"]
public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
private_db_subnet_cidrs  = ["10.0.20.0/24", "10.0.21.0/24"]

db_name           = "autoserve"
db_username       = "autoserve_admin"
db_instance_class = "db.t3.micro"