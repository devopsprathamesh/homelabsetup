variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "deletion_window_in_days" {
  type    = number
  default = 30
}

variable "multi_region" {
  description = "Create a multi-region primary key (replicate with aws_kms_replica_key in the DR region's kms module invocation)."
  type        = bool
  default     = false
}

variable "primary_key_arn" {
  description = "If set, this invocation creates an aws_kms_replica_key of the given multi-region primary key instead of a new key. Used in the DR region."
  type        = string
  default     = null
}

variable "additional_principal_arns" {
  description = "Extra IAM principals (e.g. the EKS cluster role, Velero's IRSA/Pod Identity role) allowed to use this key."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
