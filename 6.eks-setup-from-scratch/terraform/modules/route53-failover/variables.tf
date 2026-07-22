variable "mode" {
  description = "\"failover\" for active-passive DR, \"latency\" for active-active."
  type        = string
  validation {
    condition     = contains(["failover", "latency"], var.mode)
    error_message = "mode must be \"failover\" or \"latency\"."
  }
}

variable "hosted_zone_id" {
  type = string
}

variable "record_name" {
  description = "FQDN clients will actually resolve, e.g. app.example.com."
  type        = string
}

variable "health_check_path" {
  type    = string
  default = "/healthz"
}

variable "primary_region" {
  type = string
}

variable "secondary_region" {
  type = string
}

variable "primary_endpoint" {
  description = "DNS name of the primary region's ingress load balancer (Istio ingress gateway NLB/ALB)."
  type        = string
}

variable "primary_endpoint_zone_id" {
  type = string
}

variable "secondary_endpoint" {
  type = string
}

variable "secondary_endpoint_zone_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
