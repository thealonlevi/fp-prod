variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "instance_count" {
  type    = number
  default = 3
}

variable "server_port" {
  description = "Port sdk-server listens on"
  type        = number
  default     = 9090
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "sdk_server_tag" {
  description = "Git tag for mock-server, e.g. v0.1.2"
  type        = string
  default     = "v0.1.2"
}
