variable "admin_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Never 0.0.0.0/0."
  type        = list(string)
}

variable "route53_zone_arns" {
  type = list(string)
}

variable "gitops_repo_url" {
  type = string
}
