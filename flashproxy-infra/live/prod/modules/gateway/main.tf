########################
#  Inputs
########################
variable "namespace"     { type = string }
variable "gateway_image" { type = string }

########################
#  Namespace
########################
resource "kubernetes_namespace" "ns" {
  metadata { name = var.namespace }
}

########################
#  Deployment
########################
resource "kubernetes_deployment" "sdk_gateway" {
  metadata {
    name      = "sdk-gateway"
    namespace = kubernetes_namespace.ns.metadata[0].name
    labels    = { app = "sdk-gateway" }
  }

  spec {
    replicas = 2

    selector { match_labels = { app = "sdk-gateway" } }

    template {
      metadata { labels = { app = "sdk-gateway" } }

      spec {
        container {
          name  = "gateway"
          image = var.gateway_image
          port  { container_port = 8080 }

          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "200m", memory = "256Mi" }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8080
            }
            initial_delay_seconds = 5
          }
        }
      }
    }
  }
}

########################
#  Horizontal Pod Autoscaler
########################
resource "kubernetes_horizontal_pod_autoscaler_v2" "hpa" {
  metadata {
    name      = "sdk-gateway"
    namespace = kubernetes_namespace.ns.metadata[0].name
  }

  spec {
    min_replicas = 2
    max_replicas = 10

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.sdk_gateway.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type  = "Utilization"
          value = 60
        }
      }
    }
  }
}

########################
#  Service  → public NLB
########################
resource "kubernetes_service" "svc" {
  metadata {
    name      = "sdk-gateway"
    namespace = kubernetes_namespace.ns.metadata[0].name
    labels    = { app = "sdk-gateway" }

    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    }
  }

  spec {
    selector = { app = "sdk-gateway" }

    port {
      name        = "proxy"
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }
}
