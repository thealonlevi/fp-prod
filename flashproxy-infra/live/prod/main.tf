########################################
#  Root stack:  VPC  →  EKS  →  Gateway
########################################

###############################################################################
#  1. Network
###############################################################################
module "network" {
  source = "./modules/network"
}

###############################################################################
#  2. EKS cluster
###############################################################################
module "eks" {
  source             = "./modules/eks"

  cluster_name       = var.cluster_name
  eks_version        = var.eks_version
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnets
}

###############################################################################
#  3. Gateway (Deployment + Service + HPA)
#     ─────────────────────────────────────
#     Uses the **single** kubernetes provider defined in providers.tf
###############################################################################
module "gateway" {
  source        = "./modules/gateway"
  namespace     = "gateway"
  gateway_image = var.gateway_image

  depends_on = [module.eks]   # ensure control-plane is ready
}

# Optional output once the gateway module exports a DNS name
# output "gateway_nlb_dns" {
#   description = "Public DNS name of the gateway Network Load Balancer"
#   value       = module.gateway.gateway_nlb_dns
# }
