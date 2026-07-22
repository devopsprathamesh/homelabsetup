# One-time, manually-applied bootstrap. This module is intentionally NOT remote-stated
# (it creates the bucket that every other stack's backend.tf points at) and is applied
# once per region that will host a `terraform/live/<region>/*` stack.

terraform {
  required_version = ">= 1.11.0" # required for S3 native locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "state" {
  bucket = "${var.project}-tfstate-${var.region}-${data.aws_caller_identity.current.account_id}"

  # Deliberately no `force_destroy`: this bucket holds the source of truth for every
  # stack's infrastructure. Destroying it should always be a conscious, manual act.
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Keep old state versions around for rollback/forensics, but don't accumulate them forever.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
