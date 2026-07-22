# Single shared S3 bucket for Velero backups (cluster resource manifests + EBS volume
# snapshots), created once in terraform/live/global and referenced by BOTH the primary and
# DR region's platform-addons Velero installation. One bucket, not one per region: Velero
# in the primary region writes backups here; Velero in the DR region reads them to restore.
# S3 buckets are reachable cross-region within the same account, so no replication needed
# for this object — only the KMS key that encrypts it needs to be multi-region (see
# terraform/modules/kms and docs/dr-ha/02-multi-region-active-passive-dr.md).

resource "aws_s3_bucket" "velero" {
  bucket = "${var.project}-velero-backups-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket                  = aws_s3_bucket.velero.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id
  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    expiration {
      days = var.backup_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
