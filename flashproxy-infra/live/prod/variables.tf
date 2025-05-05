variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "az" {
  description = "Single AZ to run everything in"
  type        = string
  default     = "eu-central-1a"
}

variable "instance_count" {
  description = "How many sdk-gateway EC2 instances to launch"
  type        = number
  default     = 3
}

variable "gateway_port" {
  description = "Port sdk-gateway listens on (and NLB forwards)"
  type        = number
  default     = 8080
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.small"
}

variable "sdk_gateway_download_url" {
  description = "URL to the sdk-gateway binary"
  type        = string
  default     = "https://example.com/sdk-gateway-linux-amd64"
}
