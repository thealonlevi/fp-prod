############
# Networking
############

resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "sdk-gw-vpc" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = var.az
  map_public_ip_on_launch = true
  tags = { Name = "sdk-gw-public" }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt.id
}

###############
# SecurityGroup
###############

resource "aws_security_group" "sdk_sg" {
  name        = "sdk-gw-sg"
  description = "Allow inbound tcp ${var.gateway_port}"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol  = "tcp"
    from_port = var.gateway_port
    to_port   = var.gateway_port
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

##################
# Launch template
##################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }
}

resource "aws_launch_template" "sdk_lt" {
  name_prefix   = "sdk-gw-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.sdk_sg.id]

  user_data = base64encode(
    templatefile("${path.module}/userdata.tpl", {
      gateway_port             = var.gateway_port
      sdk_gateway_download_url = var.sdk_gateway_download_url
    })
  )

  lifecycle {
    create_before_destroy = true
  }
}

####################
# Auto Scaling Group
####################

resource "aws_autoscaling_group" "sdk_asg" {
  desired_capacity    = var.instance_count
  max_size            = 10
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.public.id]

  launch_template {
    id      = aws_launch_template.sdk_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.sdk_tg.arn]
  health_check_type = "EC2"
  health_check_grace_period = 60
  availability_zones        = [var.az]

  tag {
    key                 = "Name"
    value               = "sdk-gateway"
    propagate_at_launch = true
  }
}

#####################
# Network LoadBalancer
#####################

resource "aws_lb" "sdk_nlb" {
  name               = "sdk-nlb"
  load_balancer_type = "network"
  subnets            = [aws_subnet.public.id]
}

resource "aws_lb_target_group" "sdk_tg" {
  name        = "sdk-tg"
  port        = var.gateway_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    protocol = "TCP"
  }
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
