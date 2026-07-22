locals {
  region       = "us-east-1"
  cluster_name = "eks-platform-prod"
  environment  = "prod"

  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]

  tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
    Project     = "eks-platform"
  }
}

data "terraform_remote_state" "global" {
  backend = "s3"
  config = {
    bucket = "eks-platform-tfstate-us-east-1-ACCOUNT_ID"
    key    = "global/terraform.tfstate"
    region = "us-east-1"
  }
}

module "vpc" {
  source = "../../../modules/vpc"

  name         = "${local.cluster_name}-vpc"
  cluster_name = local.cluster_name
  vpc_cidr     = "10.20.0.0/16"
  azs          = local.azs

  # One NAT gateway per AZ — a single NAT/AZ failure must not take out egress
  # for workloads in the other two AZs.
  single_nat_gateway = false

  tags = local.tags
}

module "kms" {
  source = "../../../modules/kms"

  cluster_name = local.cluster_name
  region       = local.region

  # Multi-region key: replicated into us-west-2 by terraform/live/us-west-2/dr-prod's
  # kms module invocation (aws_kms_replica_key), so DR-region restores of anything
  # encrypted with this key (EBS snapshots, Velero backups) can decrypt without
  # depending on the primary region being reachable. See
  # docs/dr-ha/02-multi-region-active-passive-dr.md.
  multi_region = true

  tags = local.tags
}

module "eks_cluster" {
  source = "../../../modules/eks-cluster"

  cluster_name       = local.cluster_name
  kubernetes_version = "1.32"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  intra_subnet_ids   = module.vpc.intra_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs

  kms_key_arn = module.kms.key_arn

  core_node_instance_types = ["m6i.xlarge"]
  core_node_min_size       = 3
  core_node_max_size       = 6
  core_node_desired_size   = 3

  log_retention_days = 400

  tags = local.tags
}

module "eks_core_addons" {
  source = "../../../modules/eks-core-addons"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = 3

  tags = local.tags

  depends_on = [module.eks_cluster]
}

module "eks_karpenter" {
  source = "../../../modules/eks-karpenter"

  cluster_name     = module.eks_cluster.cluster_name
  cluster_endpoint = module.eks_cluster.cluster_endpoint

  pod_identity_agent_dependency = module.eks_core_addons.pod_identity_agent_ready

  karpenter_replicas    = 2
  nodepool_cpu_limit    = "2000"
  nodepool_memory_limit = "4000Gi"

  tags = local.tags
}

module "istio" {
  source = "../../../modules/istio"

  istiod_replicas             = 3
  ingressgateway_replicas     = 3
  ingressgateway_max_replicas = 15
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

  # Primary region: schedules the backups the DR region will restore from.
  enable_velero      = true
  velero_bucket_name = data.terraform_remote_state.global.outputs.velero_bucket_name
  velero_backup_schedules = {
    daily = {
      schedule = "0 3 * * *"
      template = {
        ttl                = "720h" # 30 days
        includedNamespaces = ["*"]
        snapshotVolumes    = true
      }
    }
  }

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
  gitops_root_path       = "kubernetes/apps/app-of-apps/prod"

  depends_on = [module.platform_addons, module.observability]
}
