output "cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "istio_ingress_nlb_dns_name" {
  description = "Consumed by terraform/live/global for the Route53 failover secondary alias record."
  value       = module.istio.ingress_nlb_dns_name
}

output "istio_ingress_nlb_zone_id" {
  value = module.istio.ingress_nlb_zone_id
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name} --region us-west-2"
}
