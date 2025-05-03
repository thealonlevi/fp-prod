output "vpc_id" {
  description = "ID of the VPC created for fp-prod"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs (one per AZ)"
  value       = module.vpc.private_subnets
}
