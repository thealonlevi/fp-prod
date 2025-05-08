#################################
# main.tf – sdk-server (new tier)
#################################

#############################
# Look up existing network  #
#############################

data "aws_vpc" "gw_vpc" {
  filter {
    name   = "tag:Name"
    values = ["sdk-gw-vpc"]
  }
}

data "aws_subnet" "gw_public" {
  filter {
    name   = "tag:Name"
    values = ["sdk-gw-public"]
  }
}

########################
# Security Groups      #
########################

# Existing gateway SG
data "aws_security_group" "sdk_gw_sg" {
  filter {
    name   = "group-name"
    values = ["sdk-gw-sg"]
  }
  vpc_id = data.aws_vpc.gw_vpc.id
}

# New server SG – only traffic from gateway on 9090 (+ optional SSH)
resource "aws_security_group" "sdk_srv_sg" {
  name        = "sdk-srv-sg"
  description = "Allow TCP 9090 from sdk-gateway"
  vpc_id      = data.aws_vpc.gw_vpc.id

  ingress {
    protocol        = "tcp"
    from_port       = var.server_port
    to_port         = var.server_port
    security_groups = [data.aws_security_group.sdk_gw_sg.id]
    description     = "sdk-gateway to sdk-server"   # ASCII-only
  }

  # SSH (optional)
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

########################
# Launch Template      #
########################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }
}

resource "aws_launch_template" "sdk_srv_lt" {
  name_prefix            = "sdk-srv-"
  image_id               = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.sdk_srv_sg.id]

  user_data = base64encode(
    templatefile("${path.module}/userdata.tpl", {
      server_port    = var.server_port,
      sdk_server_tag = var.sdk_server_tag
    })
  )

  lifecycle { create_before_destroy = true }
}

##########################
# Auto Scaling Group     #
##########################

resource "aws_autoscaling_group" "sdk_srv_asg" {
  desired_capacity    = var.instance_count
  min_size            = 1
  max_size            = 10
  vpc_zone_identifier = [data.aws_subnet.gw_public.id]

  launch_template {
    id      = aws_launch_template.sdk_srv_lt.id
    version = "$Latest"
  }

  target_group_arns         = [aws_lb_target_group.sdk_srv_tg.arn]
  health_check_type         = "EC2"
  health_check_grace_period = 60

  tag {
    key                 = "Name"
    value               = "sdk-server"
    propagate_at_launch = true
  }
}

############################
# Network Load Balancer    #
############################

resource "aws_lb" "sdk_srv_nlb" {
  name               = "sdk-server-nlb"
  load_balancer_type = "network"
  subnets            = [data.aws_subnet.gw_public.id]
}

resource "aws_lb_target_group" "sdk_srv_tg" {
  name        = "sdk-server-tg"
  port        = var.server_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.gw_vpc.id

  health_check { protocol = "TCP" }
}

resource "aws_lb_listener" "sdk_srv_listener" {
  load_balancer_arn = aws_lb.sdk_srv_nlb.arn
  port              = var.server_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sdk_srv_tg.arn
  }
}
