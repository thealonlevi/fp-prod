#################################
# main.tf – sdk-gateway (revised)
#################################

#############################
# Networking ─ VPC & Subnet #
#############################

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

########################
# Security Group       #
########################

resource "aws_security_group" "sdk_sg" {
  name        = "sdk-gw-sg"
  description = "Allow inbound TCP 8080"
  vpc_id      = aws_vpc.main.id

  # Public traffic to the gateway listener
  ingress {
    protocol    = "tcp"
    from_port   = var.gateway_port
    to_port     = var.gateway_port
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH (optional, tighten in production)
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
# Bring in the sdk-server NLB DNS via remote state
##############################################
# ⚠️  Adjust the backend block to match your state storage.
#     If sdk-server is in the same state file, remove this and
#     reference the resource directly.
data "terraform_remote_state" "sdk_server" {
  backend = "s3"
  config = {
    bucket = "flashproxy-prod-terraform-state"
    key    = "live/prod/sdk-server/terraform.tfstate"
    region = var.aws_region
  }
}

resource "aws_launch_template" "sdk_lt" {
  name_prefix            = "sdk-gw-"
  image_id               = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.sdk_sg.id]

  user_data = base64encode(
    templatefile(
      "${path.module}/userdata.tpl",
      {
        gateway_port        = var.gateway_port,
        sdk_gateway_tag     = var.sdk_gateway_tag,
        # compile-time upstream injected via -ldflags
        sdk_server_endpoint = "${data.terraform_remote_state.sdk_server.outputs.sdk_server_endpoint}:9090"
      }
    )
  )

  lifecycle { create_before_destroy = true }
}

##########################
# Auto Scaling Group     #
##########################

resource "aws_autoscaling_group" "sdk_asg" {
  desired_capacity    = var.instance_count
  min_size            = 1
  max_size            = 10
  vpc_zone_identifier = [aws_subnet.public.id]

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
  subnets            = [aws_subnet.public.id]
}

resource "aws_lb_target_group" "sdk_tg" {
  name        = "sdk-tg"
  port        = var.gateway_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

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
