output "cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr_block
}

output "kms_key_arn" {
  description = "Referenced by terraform/live/us-west-2/dr-prod to create the multi-region replica key."
  value       = module.kms.key_arn
}

output "amp_workspace_id" {
  value = module.observability.amp_workspace_id
}

output "amg_workspace_endpoint" {
  value = module.observability.amg_workspace_endpoint
}

output "istio_ingress_nlb_dns_name" {
  description = "Consumed by terraform/live/global for the Route53 failover primary alias record."
  value       = module.istio.ingress_nlb_dns_name
}

output "istio_ingress_nlb_zone_id" {
  value = module.istio.ingress_nlb_zone_id
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name} --region us-east-1"
}
