terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket       = "eks-platform-tfstate-us-east-1-ACCOUNT_ID" # global stack's state lives in the primary region's bucket
    key          = "global/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
