# Outputs the public‐facing NLB DNS name for clients
output "sdk_gateway_endpoint" {
  description = "DNS name clients should connect to"
  value       = aws_lb.sdk_nlb.dns_name
}
