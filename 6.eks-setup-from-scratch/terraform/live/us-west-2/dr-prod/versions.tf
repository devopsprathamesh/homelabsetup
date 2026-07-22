terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket       = "eks-platform-tfstate-us-west-2-ACCOUNT_ID" # separate bucket, separate region — see state-backend-bootstrap
    key          = "us-west-2/dr-prod/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }
}
