variable "project" {
  type    = string
  default = "eks-platform"
}

variable "kms_key_arn" {
  description = "Multi-region KMS key ARN to encrypt this bucket with, so both regions' Velero can decrypt."
  type        = string
}

variable "backup_retention_days" {
  type    = number
  default = 90
}
