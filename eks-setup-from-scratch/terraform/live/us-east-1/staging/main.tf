locals {
  region       = "us-east-1"
  cluster_name = "eks-platform-staging"
  environment  = "staging"

  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]

  tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
    Project     = "eks-platform"
  }
}

module "vpc" {
  source = "../../../modules/vpc"

  name         = "${local.cluster_name}-vpc"
  cluster_name = local.cluster_name
  vpc_cidr     = "10.10.0.0/16"
  azs          = local.azs

  # Staging is cost-optimized: one shared NAT gateway instead of one per AZ.
  # Never set this true in prod/dr-prod.
  single_nat_gateway = true

  tags = local.tags
}

module "kms" {
  source = "../../../modules/kms"

  cluster_name = local.cluster_name
  region       = local.region
  multi_region = false # staging never needs DR replication

  tags = local.tags
}

module "eks_cluster" {
  source = "../../../modules/eks-cluster"

  cluster_name       = local.cluster_name
  kubernetes_version = "1.32"

  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  intra_subnet_ids    = module.vpc.intra_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs

  kms_key_arn = module.kms.key_arn

  core_node_instance_types = ["m6i.large"]
  core_node_min_size       = 2
  core_node_max_size       = 4
  core_node_desired_size   = 2

  tags = local.tags
}

module "eks_core_addons" {
  source = "../../../modules/eks-core-addons"

  cluster_name = module.eks_cluster.cluster_name

  tags = local.tags

  depends_on = [module.eks_cluster]
}

module "eks_karpenter" {
  source = "../../../modules/eks-karpenter"

  cluster_name     = module.eks_cluster.cluster_name
  cluster_endpoint = module.eks_cluster.cluster_endpoint

  pod_identity_agent_dependency = module.eks_core_addons.pod_identity_agent_ready

  nodepool_cpu_limit    = "200"
  nodepool_memory_limit = "400Gi"

  tags = local.tags
}

module "istio" {
  source = "../../../modules/istio"

  istiod_replicas             = 1 # staging: single replica, prod uses 2+
  ingressgateway_replicas     = 1
  ingressgateway_max_replicas = 3
  ingressgateway_lb_name      = "${local.cluster_name}-ingress"

  depends_on = [module.eks_core_addons]
}

module "platform_addons" {
  source = "../../../modules/platform-addons"

  cluster_name      = module.eks_cluster.cluster_name
  cluster_endpoint  = module.eks_cluster.cluster_endpoint
  cluster_version   = module.eks_cluster.cluster_version
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  region            = local.region

  route53_zone_arns = var.route53_zone_arns

  tags = local.tags

  depends_on = [module.istio]
}

module "observability" {
  source = "../../../modules/observability-amp-amg"

  cluster_name = module.eks_cluster.cluster_name
  region       = local.region

  tags = local.tags

  depends_on = [module.eks_karpenter]
}

module "argocd_bootstrap" {
  source = "../../../modules/argocd-bootstrap"

  gitops_repo_url        = var.gitops_repo_url
  gitops_target_revision = "main"
  gitops_root_path       = "kubernetes/apps/app-of-apps/staging"

  depends_on = [module.platform_addons, module.observability]
}
