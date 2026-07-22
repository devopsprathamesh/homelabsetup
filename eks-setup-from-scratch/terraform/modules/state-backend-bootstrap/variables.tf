variable "project" {
  description = "Short project name used as a prefix for the state bucket."
  type        = string
  default     = "eks-platform"
}

variable "region" {
  description = "AWS region this state backend serves."
  type        = string
}
