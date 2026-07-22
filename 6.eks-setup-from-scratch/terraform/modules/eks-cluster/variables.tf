variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.32"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Subnets worker nodes/pods live in."
  type        = list(string)
}

variable "intra_subnet_ids" {
  description = "No-egress subnets used for the EKS control plane cross-account ENIs."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Whether the API server is reachable from outside the VPC at all. Prefer false + a bastion/VPN/Cloud9 in real prod; true+CIDR-restricted is the common pragmatic default."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Never leave this as 0.0.0.0/0 in prod."
  type        = list(string)
  default     = []
}

variable "access_entries" {
  description = "Additional IAM principals to grant cluster access via EKS access entries."
  type        = any
  default     = {}
}

variable "kms_key_arn" {
  description = "KMS key ARN for secrets envelope encryption and CloudWatch log group encryption."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 400
}

variable "core_node_instance_types" {
  type    = list(string)
  default = ["m6i.large"]
}

variable "core_node_min_size" {
  type    = number
  default = 3
}

variable "core_node_max_size" {
  type    = number
  default = 6
}

variable "core_node_desired_size" {
  type    = number
  default = 3
}

variable "tags" {
  type    = map(string)
  default = {}
}
