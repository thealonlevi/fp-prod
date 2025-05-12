terraform {
  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 0.44"
    }
  }
}

provider "ovh" {
  endpoint          = "ovh-eu"
  application_key   = var.ovh_app_key
  application_secret= var.ovh_app_secret
  consumer_key      = var.ovh_consumer_key
}

resource "ovh_dedicated_server_order" "edge" {        # Bare-metal order  :contentReference[oaicite:4]{index=4}
  service_name = var.project
  plan_code    = var.plan_code
  datacentre   = var.datacentre
  duration     = "P1M"            # monthly rental
}

resource "ovh_dedicated_server_install_task" "os" {   # Cloud-init reinstall  :contentReference[oaicite:5]{index=5}
  server_id     = ovh_dedicated_server_order.edge.id
  template_name = "debian12"
  ssh_key       = file(var.ssh_pub_key_path)
  user_data     = file("${path.module}/cloud-init.yaml")
}

data "ovh_dedicated_server" "edge" {                  # Grab public IPv4  :contentReference[oaicite:6]{index=6}
  id = ovh_dedicated_server_order.edge.id
}
