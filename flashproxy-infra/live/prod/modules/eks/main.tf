########################################
#  Input variables                      #
########################################
variable "cluster_name"        { description = "EKS cluster name";      type = string }
variable "eks_version"         { description = "Kubernetes version";    type = string; default = "1.30" }
variable "vpc_id"              { description = "VPC ID";               type = string }
variable "private_subnet_ids"  { description = "Private subnet IDs";    type = list(string) }

########################################
#  EKS control-plane + node group
########################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.eks_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  enable_cluster_creator_admin_permissions = true
  enable_irsa = true

  eks_managed_node_groups = {
    ng-c7g-large = {
      desired_size   = 2
      min_size       = 2
      max_size       = 6
      instance_types = ["c7g.large"]
      ami_type       = "AL2023_ARM_64_STANDARD"

      iam_role_additional_policies = {
        ecr = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }
}

########################################
#  IAM role for AWS LB Controller
########################################
data "aws_iam_policy_document" "lb_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals { type = "Federated" identifiers = [module.eks.oidc_provider_arn] }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${var.cluster_name}-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume.json
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

########################################
#  Cluster data for Helm provider
########################################
data "aws_eks_cluster" "auth"  { name = module.eks.cluster_name }
data "aws_eks_cluster_auth" "auth" { name = module.eks.cluster_name }

########################################
#  Helm provider bound directly to EKS
########################################
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.auth.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.auth.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.auth.token
  }
}

########################################
#  Install AWS Load Balancer Controller
########################################
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.9.0"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.lb_controller.arn
  }

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.lb_controller
  ]
}

########################################
#  Outputs
########################################
output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "API endpoint"
}

output "cluster_certificate_authority_data" {
  value       = module.eks.cluster_certificate_authority_data
  description = "Base64-encoded cluster CA"
}

output "oidc_provider_arn" {
  value       = module.eks.oidc_provider_arn
  description = "Cluster OIDC provider ARN"
}
