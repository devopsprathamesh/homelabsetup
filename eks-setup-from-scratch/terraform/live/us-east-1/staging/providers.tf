provider "aws" {
  region = local.region

  default_tags {
    tags = local.tags
  }
}

# All three Kubernetes-facing providers authenticate via short-lived tokens from
# `aws eks get-token`, rather than a static kubeconfig — no long-lived credentials to
# rotate or leak, and it works identically in CI as on a laptop with the right IAM role.
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
