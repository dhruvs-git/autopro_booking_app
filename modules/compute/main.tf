# Fetching the latest AMI for the EC2

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


# ALB
resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}


# Target Group
resource "aws_lb_target_group" "main" {
  name     = "${var.name_prefix}-target-group"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {

    enabled             = true
    path                = "/health"
    port = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.name_prefix}-target-group"
  }
}


# The ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"        # port internet hits
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}



#LAUNCH TEMPLATE

resource "aws_launch_template" "main" {
  name          = "${var.name_prefix}-launch-template"
  description   = "Launch template for Autoserve Flask app"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.ec2_instance_type

  vpc_security_group_ids = [var.ec2_sg_id]

  iam_instance_profile {
    name = var.ec2_instance_profile_name
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    secret_arn = var.db_secret_arn
    region = var.region
    }))


  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp2"
      encrypted = true
      delete_on_termination = true

    }
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  update_default_version = true  

  lifecycle {
    create_before_destroy = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name_prefix}-instance"
    }
  }

  tags = {
    Name = "${var.name_prefix}-launch-template"
  }
}




#AUTO SCALING GROUP 
resource "aws_autoscaling_group" "main" {
  name = "${var.name_prefix}-asg"

  # --- Capacity ---
  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  # --- Network ---
  vpc_zone_identifier = var.private_app_subnet_ids

  # --- Launch Template ---
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  # --- ALB Integration ---
  target_group_arns = [aws_lb_target_group.main.arn]
  health_check_type = "ELB"      # use ALB health checks, not just EC2
  health_check_grace_period = 300   # seconds before health check starts


  lifecycle {
    create_before_destroy = true
  }

  # --- Instance Refresh (rolling updates) ---
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-asg-instance"
    propagate_at_launch = true   # tag gets applied to every EC2 launched
  }

}