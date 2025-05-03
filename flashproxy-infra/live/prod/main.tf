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
###############################################################################
module "gateway" {
  source        = "./modules/gateway"
  namespace     = "gateway"
  gateway_image = var.gateway_image

  # Use the aliased provider
  providers = {
    kubernetes = kubernetes.eks   # <- points to the EKS endpoint
  }

  depends_on = [module.eks]
}

###############################################################################
#  Optional output once gateway module exports it
###############################################################################
# output "gateway_nlb_dns" {
#   description = "Public DNS name of the gateway Network Load Balancer"
#   value       = module.gateway.gateway_nlb_dns
# }
