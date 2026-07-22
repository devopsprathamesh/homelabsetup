# Region-agnostic resources, applied AFTER both terraform/live/us-east-1/prod and
# terraform/live/us-west-2/dr-prod exist (this stack reads their outputs via
# terraform_remote_state). See docs/dr-ha/02-multi-region-active-passive-dr.md for the
# full apply-order rationale.

locals {
  tags = {
    ManagedBy = "terraform"
    Project   = "eks-platform"
    Scope     = "global"
  }
}

# Dedicated multi-region key for Velero backups — deliberately separate from each
# cluster's own EKS secrets-encryption key, so the backup bucket's key lifecycle isn't
# coupled to any single cluster's lifecycle.
module "backup_kms" {
  source = "../../modules/kms"

  cluster_name = "eks-platform-backups"
  region       = "us-east-1"
  multi_region = true

  tags = local.tags
}

module "backup_bucket" {
  source = "../../modules/backup-bucket"

  kms_key_arn            = module.backup_kms.key_arn
  backup_retention_days  = 90
}

data "aws_route53_zone" "primary" {
  count = var.route53_zone_name != "" ? 1 : 0
  name  = var.route53_zone_name
}

data "terraform_remote_state" "prod" {
  count   = var.enable_dr_failover_dns ? 1 : 0
  backend = "s3"
  config = {
    bucket = "eks-platform-tfstate-us-east-1-ACCOUNT_ID"
    key    = "us-east-1/prod/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "dr_prod" {
  count   = var.enable_dr_failover_dns ? 1 : 0
  backend = "s3"
  config = {
    bucket = "eks-platform-tfstate-us-west-2-ACCOUNT_ID"
    key    = "us-west-2/dr-prod/terraform.tfstate"
    region = "us-west-2"
  }
}

# Failover DNS: only enabled once both regions exist and you've captured their Istio
# ingress gateway NLB DNS names as outputs (see docs/runbooks/dr-failover-runbook.md for
# how this record flips during an actual failover).
module "dns_failover" {
  count  = var.enable_dr_failover_dns ? 1 : 0
  source = "../../modules/route53-failover"

  mode           = "failover"
  hosted_zone_id = data.aws_route53_zone.primary[0].zone_id
  record_name    = var.app_fqdn

  primary_region   = "us-east-1"
  secondary_region = "us-west-2"

  primary_endpoint           = data.terraform_remote_state.prod[0].outputs.istio_ingress_nlb_dns_name
  primary_endpoint_zone_id   = data.terraform_remote_state.prod[0].outputs.istio_ingress_nlb_zone_id
  secondary_endpoint         = data.terraform_remote_state.dr_prod[0].outputs.istio_ingress_nlb_dns_name
  secondary_endpoint_zone_id = data.terraform_remote_state.dr_prod[0].outputs.istio_ingress_nlb_zone_id

  tags = local.tags
}
