output "istio_system_namespace" {
  value = kubernetes_namespace.istio_system.metadata[0].name
}

output "istio_ingress_namespace" {
  value = kubernetes_namespace.istio_ingress.metadata[0].name
}

output "ingressgateway_release_name" {
  value = helm_release.istio_ingressgateway.name
}

output "ingress_nlb_dns_name" {
  value = data.aws_lb.ingress.dns_name
}

output "ingress_nlb_zone_id" {
  value = data.aws_lb.ingress.zone_id
}
