variable "istio_version" {
  type    = string
  default = "1.30.0"
}

variable "network_name" {
  type    = string
  default = "network1"
}

variable "istiod_replicas" {
  description = "Run >=2 for control-plane HA across AZs."
  type        = number
  default     = 2
}

variable "ingressgateway_replicas" {
  type    = number
  default = 3
}

variable "ingressgateway_max_replicas" {
  type    = number
  default = 10
}

variable "ingressgateway_lb_name" {
  description = "Fixed NLB name so it can be looked up afterward via the aws_lb data source (Route53 failover records need its DNS name + hosted zone ID)."
  type        = string
}
