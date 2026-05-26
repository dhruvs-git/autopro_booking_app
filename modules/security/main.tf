#----------------------------------------
#               ALB - SG
#----------------------------------------

resource "aws_security_group" "alb" {
  name = "${var.name_prefix}-alb-sg"
  description = "ALB-sg accepts traffic from the internet and forwards to ec2 on port 5000"
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description = "HTTPS from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description = "HTTP from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

 #we use port 5000 as the app is using flask and its default port is 5000
resource "aws_vpc_security_group_egress_rule" "alb_to_ec2" {
  security_group_id = aws_security_group.alb.id
  description = "forward to ec2 flask on 5000"
  from_port         = 5000
  ip_protocol       = "tcp"
  to_port           = 5000
  referenced_security_group_id = aws_security_group.ec2.id
  
 
}


#----------------------------------------
#               EC2 - SG
#----------------------------------------

resource "aws_security_group" "ec2" {
  name = "${var.name_prefix}-ec2-sg"
  description = "EC2 - accepts from ALB only, all outbound for AWS APIs"
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-ec2-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb" {
  security_group_id = aws_security_group.ec2.id
  description = "FLASK traffic from alb only"
  from_port         = 5000
  ip_protocol       = "tcp"
  to_port           = 5000
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "ec2_all_outbound" {
  security_group_id = aws_security_group.ec2.id
  description = "ALL OUTBOUND - for aws apis and package installs"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}


#----------------------------------------
#               RDS - SG
#----------------------------------------

resource "aws_security_group" "rds" {
  name = "${var.name_prefix}-rds-sg"
  description = "RDS - accepts from EC2 only port 3306"
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-rds-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ec2" {
  security_group_id = aws_security_group.rds.id
  description = "MYSQL from EC2 on 3306"
  from_port         = 3306
  ip_protocol       = "tcp"
  to_port           = 3306
  referenced_security_group_id = aws_security_group.ec2.id
}

# NO EGRESS AS WE DONT WANT TO INITIATE CONNECTION FROM RDS
/* As inbound from ec2 is allowed so outbound to ec2 is also 
    allowed stateful behavior of security groups */


#----------------------------------------
#               REDIS - SG
#----------------------------------------

resource "aws_security_group" "redis" {
  name = "${var.name_prefix}-redis-sg"
  description = "REDIS - accepts from EC2 only port 6379"
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-redis-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_ec2" {
  security_group_id = aws_security_group.redis.id
  description = "Redis from EC2 on 6379"
  from_port         = 6379
  ip_protocol       = "tcp"
  to_port           = 6379
  referenced_security_group_id = aws_security_group.ec2.id
}