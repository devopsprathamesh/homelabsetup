# KMS key used for two things: (1) EKS `cluster_encryption_config` envelope encryption
# of Kubernetes Secrets in etcd, and (2) the CloudWatch log group holding control-plane logs.
#
# DR note: secrets in etcd are region-local and are NOT replicated by a multi-region KMS key
# by themselves — a multi-region key only lets the *key material* exist in both regions so a
# DR-region cluster (or a restore job) can decrypt anything that WAS explicitly copied there
# (e.g. an EBS snapshot or a Velero backup encrypted with this key). See
# docs/dr-ha/02-multi-region-active-passive-dr.md for the full explanation.

resource "aws_kms_key" "this" {
  count = var.primary_key_arn == null ? 1 : 0

  description             = "Envelope encryption key for ${var.cluster_name} (EKS secrets + control-plane logs)"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  multi_region            = var.multi_region

  policy = data.aws_iam_policy_document.key_policy.json

  tags = var.tags
}

# DR-region invocation: replicate an existing multi-region primary key's key material into
# this region instead of creating a brand-new key. Set var.primary_key_arn to the primary
# region's kms module `key_arn` output (must itself have been created with multi_region=true).
resource "aws_kms_replica_key" "this" {
  count = var.primary_key_arn != null ? 1 : 0

  description             = "Replica of ${var.primary_key_arn} for ${var.cluster_name}"
  primary_key_arn         = var.primary_key_arn
  deletion_window_in_days = var.deletion_window_in_days

  policy = data.aws_iam_policy_document.key_policy.json

  tags = var.tags
}

locals {
  key_id  = var.primary_key_arn == null ? aws_kms_key.this[0].key_id : aws_kms_replica_key.this[0].key_id
  key_arn = var.primary_key_arn == null ? aws_kms_key.this[0].arn : aws_kms_replica_key.this[0].arn
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = local.key_id
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "key_policy" {
  # Root account retains full administrative access — required so the key is never
  # accidentally locked out of by an over-narrow policy.
  statement {
    sid    = "EnableRootAccountFullAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # CloudWatch Logs needs to use the key to encrypt the control-plane log group.
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  # Additional principals (e.g. the EKS cluster IAM role) are granted explicitly by
  # the caller via var.additional_principal_arns, so the eks-cluster module doesn't
  # need to reach back into this module's internals.
  dynamic "statement" {
    for_each = length(var.additional_principal_arns) > 0 ? [1] : []
    content {
      sid    = "AllowAdditionalPrincipals"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.additional_principal_arns
      }
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]
      resources = ["*"]
    }
  }
}
