#################################
# main.tf – sdk-gateway (network-layer decoupled)
# • Assumes VPC & subnet are pre-created by live/prod/network
# • Keeps warm-up + extended TF timeout
#################################

#############################
# Look up shared VPC/Subnet #
#############################

data "aws_vpc" "gw" {
  filter {
    name   = "tag:Name"
    values = ["sdk-gw-vpc"]
  }
}

data "aws_subnet" "public" {
  filter {
    name   = "tag:Name"
    values = ["sdk-gw-public"]
  }
}

########################
# Security Group       #
########################

resource "aws_security_group" "sdk_sg" {
  name_prefix = "sdk-gw-"                       # avoid duplicate-name clashes
  description = "Allow inbound TCP 8080"
  vpc_id      = data.aws_vpc.gw.id

  ingress {
    protocol    = "tcp"
    from_port   = var.gateway_port
    to_port     = var.gateway_port
    cidr_blocks = ["0.0.0.0/0"]
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

##############################################
# Discover sdk-server NLB in the same account
##############################################
data "aws_lb" "sdk_server" {
  name = "sdk-server-nlb"
}

resource "aws_launch_template" "sdk_lt" {
  name_prefix            = "sdk-gw-"
  image_id               = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.sdk_sg.id]

  user_data = base64encode(
    templatefile("${path.module}/userdata.tpl", {
      gateway_port        = var.gateway_port,
      sdk_gateway_tag     = var.sdk_gateway_tag,
      sdk_server_endpoint = "${data.aws_lb.sdk_server.dns_name}:9090"
    })
  )

  lifecycle {
    create_before_destroy = true
  }
}

##########################
# Auto Scaling Group     #
##########################

resource "aws_autoscaling_group" "sdk_asg" {
  desired_capacity          = var.instance_count
  min_size                  = 1
  max_size                  = 10
  vpc_zone_identifier       = [data.aws_subnet.public.id]
  wait_for_capacity_timeout = "25m"
  default_instance_warmup   = 600   # 10-min warm-up

  launch_template {
    id      = aws_launch_template.sdk_lt.id
    version = "$Latest"
  }

  target_group_arns         = [aws_lb_target_group.sdk_tg.arn]
  health_check_type         = "EC2"
  health_check_grace_period = 60

  tag {
    key                 = "Name"
    value               = "sdk-gateway"
    propagate_at_launch = true
  }
}

############################
# Network Load Balancer    #
############################

resource "aws_lb" "sdk_nlb" {
  name               = "sdk-nlb"
  load_balancer_type = "network"
  subnets            = [data.aws_subnet.public.id]
}

resource "aws_lb_target_group" "sdk_tg" {
  name        = "sdk-tg"
  port        = var.gateway_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.gw.id

  health_check { protocol = "TCP" }
}

resource "aws_lb_listener" "sdk_listener" {
  load_balancer_arn = aws_lb.sdk_nlb.arn
  port              = var.gateway_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sdk_tg.arn
  }
}
