output "sdk_server_endpoint" {
  description = "DNS name sdk-gateway should forward to"
  value       = aws_lb.sdk_srv_nlb.dns_name
}
