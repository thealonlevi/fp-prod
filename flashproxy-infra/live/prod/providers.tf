###############################################################################
#  Terraform backend + required providers
###############################################################################
terraform {
  backend "s3" {
    bucket         = "fp-prod-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "fp-prod-tf-locks"
    profile        = "fp-prod"               # backend uses fp-prod profile
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
#  Live EKS cluster details (needed by providers)
###############################################################################
data "aws_eks_cluster" "eks" {
  name       = var.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "eks" {
  name       = var.cluster_name
  depends_on = [module.eks]
}

###############################################################################
#  Kubernetes provider bound to EKS  (alias = "eks")
###############################################################################
provider "kubernetes" {
  alias                  = "eks"                # << important
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", var.cluster_name,
      "--region",       "eu-central-1",
      "--profile",      "fp-prod"
    ]
  }
}

###############################################################################
#  Helm provider (uses same exec profile)
###############################################################################
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", var.cluster_name,
        "--region",       "eu-central-1",
        "--profile",      "fp-prod"
      ]
    }
  }
}
