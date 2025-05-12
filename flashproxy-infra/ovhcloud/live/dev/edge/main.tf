###############################################################################
# Terraform & provider
###############################################################################
terraform {
  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = ">= 0.51.0"
    }
  }
}

provider "ovh" {
  endpoint          = "ovh-eu"
  application_key   = var.ovh_app_key
  application_secret= var.ovh_app_secret
  consumer_key      = var.ovh_consumer_key
}

###############################################################################
# 0.  SSH key – uploaded once, re-used for every reinstall
###############################################################################
resource "ovh_me_ssh_key" "edge_key" {
  name       = "flash-edge"
  public_key = file(var.ssh_pub_key_path)
}

###############################################################################
# 1.  Build a cart and drop a SYS-LE-1 offer inside
###############################################################################
resource "ovh_order_cart" "cart" {
  ovh_subsidiary = "DE"                  # Any EU subsidiary is fine
  description    = "FlashProxy edge dev"
}

resource "ovh_order_cart_add" "server_offer" {
  cart_id      = ovh_order_cart.cart.id
  plan_code    = var.plan_code           # → "SYS-LE-1"
  duration     = "P1M"                   # 1-month rental
  pricing_mode = "default"
  quantity     = 1

  configuration {
    label = "datacenter"
    value = var.datacentre               # → "de1"
  }
}

resource "ovh_order_cart_checkout" "checkout" {
  cart_id = ovh_order_cart.cart.id

  # Auto-pay with your preferred payment method (card, credits, etc.)
  auto_pay_with_preferred_payment_method = true

  # Wait until the order is fully processed
  depends_on = [ovh_order_cart_add.server_offer]
}

###############################################################################
# 2.  Re-install the newly delivered server with cloud-init
###############################################################################
resource "ovh_dedicated_server_install_task" "install" {
  # service_name appears in the checkout’s resource_id (nsXXXX*.ip-XX-XX-XX.eu)
  service_name  = ovh_order_cart_add.server_offer.resource_id

  template_name = "debian12"
  hostname      = "flash-edge-dev"

  ssh_key_name  = ovh_me_ssh_key.edge_key.name
  user_data     = file("./cloud-init.yaml")

  depends_on    = [ovh_order_cart_checkout.checkout]
}

###############################################################################
# 3.  Read back the server details (IPv4)
###############################################################################
data "ovh_dedicated_server" "edge" {
  id = ovh_order_cart_add.server_offer.resource_id
  depends_on = [ovh_dedicated_server_install_task.install]
}

output "edge_public_ipv4" {
  value       = data.ovh_dedicated_server.edge.ipv4
  description = "Public IPv4 address of the dev edge node"
}
