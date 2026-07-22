variable "route53_zone_name" {
  description = "Existing hosted zone domain name (e.g. example.com) to look up. Leave \"\" if not managing failover DNS from this repo yet."
  type        = string
  default     = ""
}

variable "app_fqdn" {
  description = "Public FQDN clients resolve, e.g. app.example.com."
  type        = string
  default     = ""
}

variable "enable_dr_failover_dns" {
  description = "Only set true once both terraform/live/us-east-1/prod and terraform/live/us-west-2/dr-prod have been applied at least once — this stack reads their outputs. First apply of this stack should leave it false (it only needs to create the backup bucket + KMS key at that point)."
  type        = bool
  default     = false
}
