provider "aws" {
  region = local.region

  default_tags {
    tags = local.tags
  }
}

# Reads the primary (us-east-1/prod) region's state to pick up its multi-region KMS key
# ARN and VPC CIDR (for a non-overlapping DR VPC CIDR and Velero/backup wiring). This is
# the documented, explicit alternative to SSM Parameter Store replication mentioned in
# docs/dr-ha/02-multi-region-active-passive-dr.md — either works, this repo picks
# terraform_remote_state for simplicity since both stacks are in the same repo/account.
data "terraform_remote_state" "primary" {
  backend = "s3"
  config = {
    bucket = "eks-platform-tfstate-us-east-1-ACCOUNT_ID"
    key    = "us-east-1/prod/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name, "--region", local.region]
  }
}

provider "helm" {
  # Helm provider v3 changed `kubernetes` from a nested block to an object-typed
  # attribute (`kubernetes = { ... }`) — do not "fix" this back to block syntax.
  kubernetes = {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name, "--region", local.region]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name, "--region", local.region]
  }
}
