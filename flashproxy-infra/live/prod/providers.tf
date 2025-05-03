###############################################################################
#  Terraform backend + required providers
###############################################################################
terraform {
  backend "s3" {
    bucket         = "fp-prod-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "fp-prod-tf-locks"
    profile        = "fp-prod"
  }

  required_providers {
    aws        = { source = "hashicorp/aws",        version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    helm       = { source = "hashicorp/helm",       version = "~> 2.13" }
  }
}

###############################################################################
#  AWS provider (shared by all modules)
###############################################################################
provider "aws" {
  region  = "eu-central-1"
  profile = "fp-prod"
}

###############################################################################
#  Data sources — pull live connection info from the EKS cluster
###############################################################################
data "aws_eks_cluster" "eks" {
  name       = var.cluster_name
  depends_on = [module.eks]   # wait until the cluster exists
}

data "aws_eks_cluster_auth" "eks" {
  name       = var.cluster_name
  depends_on = [module.eks]
}

###############################################################################
#  Kubernetes provider wired straight to EKS (no local kube-config required)
###############################################################################
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}
