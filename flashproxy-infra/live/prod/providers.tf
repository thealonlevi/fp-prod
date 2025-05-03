###############################################################################
#  Terraform backend + required providers
###############################################################################
terraform {
  backend "s3" {
    bucket         = "fp-prod-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "fp-prod-tf-locks"
    # profile line removed → the EC2 instance-profile (or your local
    # AWS creds) will be used automatically
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
  region = "eu-central-1"
  # no profile → uses instance-role on the runner or your local env vars
}

###############################################################################
#  Live EKS cluster details (for providers below)
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
#  Kubernetes provider wired straight to EKS
###############################################################################
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)

  # obtain a fresh auth token for every call via the AWS CLI exec plugin
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name", var.cluster_name,
      "--region",       "eu-central-1"
    ]
  }
}

###############################################################################
#  Helm provider (inherits the same EKS connection)
###############################################################################
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name", var.cluster_name,
        "--region",       "eu-central-1"
      ]
    }
  }
}
