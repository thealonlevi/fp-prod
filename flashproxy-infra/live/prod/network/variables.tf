variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "az" {
  description = "AZ for the public subnet"
  type        = string
  default     = "eu-central-1a"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}
