variable "admin_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint (office/VPN egress IPs). Never 0.0.0.0/0."
  type        = list(string)
}

variable "route53_zone_arns" {
  description = "Hosted zone ARNs external-dns/cert-manager may write to for this environment."
  type        = list(string)
}

variable "gitops_repo_url" {
  description = "Git URL of this repository, e.g. https://github.com/<org>/eks-setup-from-scratch.git"
  type        = string
}
