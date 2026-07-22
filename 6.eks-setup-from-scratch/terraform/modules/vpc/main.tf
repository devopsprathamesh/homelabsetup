# Thin wrapper around terraform-aws-modules/vpc/aws, pre-tagged for EKS + Karpenter
# subnet auto-discovery and ALB/NLB auto-discovery by the AWS Load Balancer Controller.
#
# Layout per AZ: 1 public subnet (ALB/NLB, NAT GW), 1 private subnet (worker nodes, pods),
# 1 intra subnet (no route to internet at all — reserved for the EKS control plane ENIs
# and anything that must never have an egress path, e.g. a future RDS/ElastiCache layer).

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.vpc_cidr

  azs             = var.azs
  public_subnets  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]
  intra_subnets   = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i + 4)]

  # HA default: one NAT gateway per AZ so a single AZ's NAT failure can't take out
  # egress for the other AZs. Set single_nat_gateway=true in cost-sensitive envs
  # (e.g. a throwaway dev stack) — never in prod/dr-prod.
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Flow logs to CloudWatch — cheap, and the first thing you want during an incident.
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  public_subnet_tags = merge(var.tags, {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })

  private_subnet_tags = merge(var.tags, {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Karpenter's default EC2NodeClass subnetSelectorTerms matches on this tag.
    "karpenter.sh/discovery" = var.cluster_name
  })

  tags = var.tags
}
