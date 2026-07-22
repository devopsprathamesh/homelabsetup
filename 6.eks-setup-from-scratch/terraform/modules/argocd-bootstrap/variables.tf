variable "argocd_chart_version" {
  type    = string
  default = "7.7.11"
}

variable "argo_rollouts_chart_version" {
  type    = string
  default = "2.38.1"
}

variable "gitops_repo_url" {
  description = "Git URL of this repository, as ArgoCD will clone it."
  type        = string
}

variable "gitops_target_revision" {
  type    = string
  default = "main"
}

variable "gitops_root_path" {
  description = "Repo path this cluster's ArgoCD root Application watches. Each environment gets its own subfolder under kubernetes/apps/app-of-apps/ so per-cluster ArgoCD instances don't all try to reconcile every environment's overlay."
  type        = string
}
