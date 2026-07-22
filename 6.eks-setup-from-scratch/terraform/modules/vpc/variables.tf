variable "name" {
  description = "VPC name."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name that will live in this VPC (used for subnet discovery tags)."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block. /16 gives room for /20 subnets across up to 16 AZ x tier combinations."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across. 3 is the minimum for real HA."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 3
    error_message = "Use at least 3 AZs for a production-grade, HA VPC."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Only set true for cost-sensitive, non-HA environments."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags applied to all VPC resources."
  type        = map(string)
  default     = {}
}
