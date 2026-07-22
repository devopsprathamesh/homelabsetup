variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "karpenter_chart_version" {
  type    = string
  default = "1.1.1"
}

variable "karpenter_replicas" {
  description = "Run at least 2 for HA of the Karpenter controller's leader election."
  type        = number
  default     = 2
}

variable "nodepool_cpu_limit" {
  description = "Hard ceiling on total vCPUs Karpenter will provision for this NodePool — a safety net against runaway scaling."
  type        = string
  default     = "1000"
}

variable "nodepool_memory_limit" {
  type    = string
  default = "1000Gi"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "pod_identity_agent_dependency" {
  description = "Pass eks-core-addons' pod_identity_agent_ready output here to enforce apply ordering (Pod Identity Agent must exist before Karpenter's Pod Identity association)."
  type        = string
}
