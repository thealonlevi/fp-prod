output "gateway_nlb_dns" {
  description = "DNS name of the Network Load Balancer in front of the gateway service"
  value       = kubernetes_service.svc.status[0].load_balancer[0].ingress[0].hostname
}
