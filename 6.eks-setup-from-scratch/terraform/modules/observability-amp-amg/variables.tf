variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "chart_version" {
  type    = string
  default = "65.5.1"
}

variable "tags" {
  type    = map(string)
  default = {}
}
