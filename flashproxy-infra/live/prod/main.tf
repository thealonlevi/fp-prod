module "network" {
  source = "./modules/network"
}

module "eks" {
  source             = "./modules/eks"
  cluster_name       = var.cluster_name
  eks_version        = var.eks_version
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnets
}

module "gateway" {
  source        = "./modules/gateway"
  namespace     = "gateway"
  gateway_image = var.gateway_image
}
