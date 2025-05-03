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
    aws        = { source = "hashicorp/aws",        version = "~> 5.0"  }
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
#  Live EKS cluster data (for kubernetes & helm providers)
###############################################################################
data "aws_eks_cluster" "eks" {
  name       = var.cluster_name
  depends_on = [module.eks]        # wait until cluster exists
}

###############################################################################
#  ── Default Kubernetes provider (used by legacy resources) ────────────────
###############################################################################
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(
    data.aws_eks_cluster.eks.certificate_authority[0].data
  )

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
#  ── Aliased provider (kubernetes.eks) – injected into gateway module ──────
###############################################################################
provider "kubernetes" {
  alias                  = "eks"   #  ← alias name
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(
    data.aws_eks_cluster.eks.certificate_authority[0].data
  )

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
#  Helm provider (re-uses the same AWS exec token)
###############################################################################
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(
      data.aws_eks_cluster.eks.certificate_authority[0].data
    )

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
