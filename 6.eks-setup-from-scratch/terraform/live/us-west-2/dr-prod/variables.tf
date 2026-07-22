variable "admin_cidrs" {
  type = list(string)
}

variable "route53_zone_arns" {
  type = list(string)
}

variable "gitops_repo_url" {
  type = string
}
