###############################################################################
#  Terraform backend + required providers
###############################################################################
terraform {
  backend "s3" {
    bucket         = "fp-prod-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "fp-prod-tf-locks"
    profile        = "fp-prod"            # state access via fp-prod profile
  }

  required_providers {
    aws        = { source = "hashicorp/aws",        version = "~> 5.0"  }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    helm       = { source = "hashicorp/helm",       version = "~> 2.13" }
  }
}

###############################################################################
#  AWS provider (shared by every module)
###############################################################################
provider "aws" {
  region  = "eu-central-1"
  profile = "fp-prod"
}

###############################################################################
#  ── Single Kubernetes provider wired to the EKS control-plane ──────────────
#      • Uses outputs from module.eks  → no self-reference / no alias needed
###############################################################################
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

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
#  Helm provider – piggybacks on the same exec-based auth
###############################################################################
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

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
