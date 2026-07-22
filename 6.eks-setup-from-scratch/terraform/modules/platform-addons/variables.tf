variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "region" {
  type = string
}

variable "route53_zone_arns" {
  description = "Hosted zone ARNs external-dns and cert-manager (DNS-01) are allowed to write to."
  type        = list(string)
}

variable "external_secrets_chart_version" {
  type    = string
  default = "0.10.7"
}

variable "fluent_bit_chart_version" {
  type    = string
  default = "0.1.34"
}

variable "enable_velero" {
  description = "Install Velero for cluster/volume backup (primary region) and restore (DR region)."
  type        = bool
  default     = false
}

variable "velero_bucket_name" {
  description = "Shared S3 bucket (terraform/modules/backup-bucket, applied once from terraform/live/global) both regions' Velero reads/writes."
  type        = string
  default     = ""
}

variable "velero_chart_version" {
  type    = string
  default = "8.1.0"
}

variable "velero_backup_schedules" {
  description = "Velero Helm chart `schedules` map. Leave empty on the DR cluster (restore-only, no schedules)."
  type        = any
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
