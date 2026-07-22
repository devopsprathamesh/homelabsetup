locals {
  region       = "us-west-2"
  cluster_name = "eks-platform-dr-prod"
  environment  = "dr-prod"

  azs = ["us-west-2a", "us-west-2b", "us-west-2c"]

  tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
    Project     = "eks-platform"
    Role        = "dr-standby"
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

data "terraform_remote_state" "prod" {
  backend = "s3"
  config = {
    bucket = "eks-platform-tfstate-us-east-1-ACCOUNT_ID"
    key    = "us-east-1/prod/terraform.tfstate"
    region = "us-east-1"
  }
}

module "vpc" {
  source = "../../../modules/vpc"

  name         = "${local.cluster_name}-vpc"
  cluster_name = local.cluster_name
  # Non-overlapping with the primary region's 10.20.0.0/16 — required if the two
  # regions are ever peered/transit-gatewayed together during failover testing.
  vpc_cidr = "10.30.0.0/16"
  azs      = local.azs

  single_nat_gateway = false

  tags = local.tags
}

module "kms" {
  source = "../../../modules/kms"

  cluster_name = local.cluster_name
  region       = local.region

  # Replica of the PRIMARY REGION'S EKS SECRETS KEY (not the Velero backup key, which has
  # its own separate multi-region key created in terraform/live/global) — NOT a new key.
  # This is what lets this cluster decrypt anything restored from a Velero backup that
  # was encrypted with the primary cluster's secrets key. See
  # docs/dr-ha/02-multi-region-active-passive-dr.md.
  primary_key_arn = data.terraform_remote_state.prod.outputs.kms_key_arn

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

  # Warm standby: enough core capacity to keep the control plane, Karpenter, Istio, and
  # ArgoCD healthy and continuously reconciling, WITHOUT paying for full production app
  # capacity until a real failover happens (Karpenter then scales workload nodes up on
  # demand — see docs/runbooks/dr-failover-runbook.md).
  core_node_instance_types = ["m6i.large"]
  core_node_min_size       = 2
  core_node_max_size       = 6
  core_node_desired_size   = 2

  log_retention_days = 400

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

  # Same ceiling as prod — during an actual failover this cluster must be able to absorb
  # 100% of production traffic, not a scaled-down fraction of it.
  karpenter_replicas    = 2
  nodepool_cpu_limit    = "2000"
  nodepool_memory_limit = "4000Gi"

  tags = local.tags
}

module "istio" {
  source = "../../../modules/istio"

  istiod_replicas             = 2
  ingressgateway_replicas     = 2
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

  # DR region: restore-only, no backup schedules — this cluster consumes the primary
  # region's backups, it doesn't produce its own competing backup set.
  enable_velero           = true
  velero_bucket_name      = data.terraform_remote_state.global.outputs.velero_bucket_name
  velero_backup_schedules = {}

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

  # Points at the SAME repo/branch as the primary region — ArgoCD in the DR cluster keeps
  # workload manifests continuously in sync, so app Deployments/Rollouts already exist
  # (usually scaled to a minimal replica count) before any failover is triggered.
  gitops_repo_url        = var.gitops_repo_url
  gitops_target_revision = "main"
  gitops_root_path       = "kubernetes/apps/app-of-apps/dr-prod"

  depends_on = [module.platform_addons, module.observability]
}
