output "vpc_id" {
  description = "Shared VPC ID"
  value       = aws_vpc.gw.id
}

output "public_subnet_id" {
  description = "Public subnet ID for gateway/server stacks"
  value       = aws_subnet.public.id
}
