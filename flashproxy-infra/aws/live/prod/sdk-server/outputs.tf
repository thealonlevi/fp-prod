output "sdk_server_endpoint" {
  description = "DNS name of the sdk-server Network Load Balancer"
  value       = aws_lb.sdk_srv_nlb.dns_name
}
