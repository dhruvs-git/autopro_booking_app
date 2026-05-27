# Generating Random Password for the database

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

#
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.secret_path}/db-credentials"
  description = "RDS database password"

  recovery_window_in_days = 7 
}


resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    host     = aws_db_instance.main.address
    port     = 3306
    dbname   = var.db_name
  })
}




resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.private_db_subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnet-group"
  }
}


resource "aws_db_instance" "main" {
  # --- Engine ---
  engine         = "mysql"
  engine_version = "8.0"

  # --- Size ---
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type = "gp2"
  storage_encrypted = true

  # --- Database ---
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result 

  # --- Network ---
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]


  publicly_accessible    = false  # never true in production
  backup_retention_period = 7
  

  multi_az = false  # true in production
  deletion_protection = false # true in production 
  skip_final_snapshot     = true  # set false in production

  tags = {
    Name = "${var.name_prefix}-rds"
  }

  lifecycle {
    ignore_changes = [ password ]
  }
}