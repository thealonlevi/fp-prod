#################################
# main.tf – shared prod network #
#################################

#############################
# VPC & Internet Gateway    #
#############################

resource "aws_vpc" "gw" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = { Name = "sdk-gw-vpc" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.gw.id
}

#############################
# Public Subnet + Route     #
#############################

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.gw.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.az
  map_public_ip_on_launch = true
  tags = { Name = "sdk-gw-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.gw.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
