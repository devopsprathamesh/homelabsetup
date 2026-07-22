variable "cluster_name" {
  type = string
}

variable "pod_identity_agent_version" {
  type    = string
  default = null # null = latest default version for the cluster's k8s version
}

variable "vpc_cni_version" {
  type    = string
  default = null
}

variable "kube_proxy_version" {
  type    = string
  default = null
}

variable "coredns_version" {
  type    = string
  default = null
}

variable "coredns_replica_count" {
  type    = number
  default = 3
}

variable "ebs_csi_version" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
