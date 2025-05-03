########################################
#  Root stack: VPC → EKS → Gateway
########################################

###############################################################################
#  1. Network (VPC, subnets, IGW/NAT, etc.)
###############################################################################
module "network" {
  source = "./modules/network"
  # (uses opinionated defaults in modules/network)
}

###############################################################################
#  2. EKS cluster + managed node group
###############################################################################
module "eks" {
  source             = "./modules/eks"

  cluster_name       = var.cluster_name
  eks_version        = var.eks_version

  # wire into the VPC created above
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnets
}

###############################################################################
#  3. Gateway (Kubernetes Deployment + Service + HPA)
###############################################################################
module "gateway" {
  source        = "./modules/gateway"
  namespace     = "gateway"
  gateway_image = var.gateway_image

  #
  # >>> important: tell the child module to use the root kubernetes provider
  #
  providers = {
    kubernetes = kubernetes
  }

  #
  # Wait until the EKS control plane exists; avoids race on first apply
  #
  depends_on = [module.eks]
}

###############################################################################
#  Optional handy outputs
###############################################################################
output "gateway_nlb_dns" {
  description = "Public DNS name of the gateway Network Load Balancer"
  value       = module.gateway.gateway_nlb_dns   # assumes module outputs this
}
