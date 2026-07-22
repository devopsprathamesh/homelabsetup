terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket       = "eks-platform-tfstate-us-east-1-ACCOUNT_ID" # replace with state-backend-bootstrap output
    key          = "us-east-1/staging/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # S3 native locking — no DynamoDB table
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }
}
