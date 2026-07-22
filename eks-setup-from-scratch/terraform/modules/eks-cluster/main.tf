# EKS control plane: encrypted secrets, full control-plane logging, private+public API
# endpoint (public restricted to an allowlist), modern access-entry authentication, and a
# small "core" managed node group that exists ONLY to host cluster-critical controllers
# (Karpenter itself, CoreDNS, the ALB Controller, Istiod, ArgoCD) — because something has
# to run before Karpenter can provision anything. Everything else (app workloads) runs on
# Karpenter-provisioned nodes. See terraform/modules/eks-karpenter and
# docs/architecture/01-compute-karpenter-vs-automode.md.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.intra_subnet_ids

  endpoint_private_access      = true
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Modern access-entry auth (replaces aws-auth ConfigMap). Cluster creator gets
  # cluster-admin automatically; add other admins via var.access_entries.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  access_entries                           = var.access_entries

  # --- Secrets encryption (KMS envelope encryption) ---
  encryption_config = {
    resources        = ["secrets"]
    provider_key_arn = var.kms_key_arn
  }

  # --- Full control-plane audit trail ---
  enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group    = true
  cloudwatch_log_group_retention_in_days = var.log_retention_days
  cloudwatch_log_group_kms_key_id        = var.kms_key_arn

  # EKS-managed addons are provisioned in the sibling eks-core-addons module so they can
  # be sequenced explicitly after Pod Identity Agent is ready. Set to {} here.
  addons = {}

  # Core system node group — small, on-demand, spread across all AZs. Everything here is
  # cluster-critical and must survive a single-AZ failure without waiting on Karpenter.
  eks_managed_node_groups = {
    core = {
      instance_types = var.core_node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.core_node_min_size
      max_size     = var.core_node_max_size
      desired_size = var.core_node_desired_size

      subnet_ids = var.private_subnet_ids

      labels = {
        "node-role" = "core"
      }

      # Keep general app workloads off the core node group; Karpenter-provisioned
      # nodes are where application pods land. Cluster-critical controllers must
      # carry the matching toleration in their Helm values.
      taints = {
        core = {
          key    = "node-role"
          value  = "core"
          effect = "NO_SCHEDULE"
        }
      }

      tags = var.tags
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  tags = var.tags
}
