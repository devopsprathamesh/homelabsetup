output "cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "amp_workspace_id" {
  value = module.observability.amp_workspace_id
}

output "amg_workspace_endpoint" {
  value = module.observability.amg_workspace_endpoint
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name} --region us-east-1"
}
