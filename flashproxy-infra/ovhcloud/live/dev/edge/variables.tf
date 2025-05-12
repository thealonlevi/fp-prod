#############################
# OVH API credentials
#############################

variable "ovh_app_key" {
  description = "OVHcloud Application Key (AK…)"
  type        = string
}

variable "ovh_app_secret" {
  description = "OVHcloud Application Secret (AS…)"
  type        = string
  sensitive   = true
}

variable "ovh_consumer_key" {
  description = "OVHcloud Consumer Key (CK…) generated for this app"
  type        = string
  sensitive   = true
}

#############################
# Deployment parameters
#############################

variable "project" {
  description = "Billing service name / NIC-handle (e.g. la2032158-ovh) or Public-Cloud project ID"
  type        = string
  default     = "la2032158-ovh"        # ← your NIC handle
}

variable "plan_code" {
  description = "Bare-metal server model to order (SYS-LE-1, ADV-7, SX-64-NVME …)"
  type        = string
  default     = "SYS-LE-1"
}

variable "datacentre" {
  description = "OVH datacentre / region code (de1, gra, rbx, waw1, …)"
  type        = string
  default     = "de1"
}

variable "ssh_pub_key_path" {
  description = "Path to the SSH *public* key that cloud-init will authorise"
  type        = string
  default     = "${path.root}/../../../ssh/id_rsa.pub"
}
