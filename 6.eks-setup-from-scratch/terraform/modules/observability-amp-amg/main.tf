# Amazon Managed Prometheus (AMP) + Amazon Managed Grafana (AMG) as the primary metrics
# backend — chosen over fully self-hosted Prometheus because AMP's storage is durable and
# regional-loss-independent, which matters directly for the DR story (see
# docs/dr-ha/02-multi-region-active-passive-dr.md: a DR-region Grafana can query the
# primary region's AMP workspace, or its own, without hand-building Prometheus HA/federation).
#
# In-cluster: a lightweight kube-prometheus-stack Prometheus (no built-in Grafana, no local
# long-term storage) does the actual scraping and remote_writes to AMP over SigV4. This is
# strictly a scrape agent, not the source of truth.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
  }
}

resource "aws_prometheus_workspace" "this" {
  alias = "${var.cluster_name}-amp"
  tags  = var.tags
}

resource "aws_grafana_workspace" "this" {
  name                     = "${var.cluster_name}-amg"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  data_sources             = ["PROMETHEUS", "CLOUDWATCH", "XRAY"]
  role_arn                 = aws_iam_role.grafana.arn
  tags                     = var.tags
}

resource "aws_iam_role" "grafana" {
  name = "${var.cluster_name}-amg-workspace"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "grafana_prometheus" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess"
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# --- In-cluster scrape agent, IAM via Pod Identity, writes to AMP over SigV4 ---
resource "aws_iam_role" "amp_remote_write" {
  name = "${var.cluster_name}-amp-remote-write"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "amp_remote_write" {
  role       = aws_iam_role.amp_remote_write.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
}

resource "aws_eks_pod_identity_association" "amp_remote_write" {
  cluster_name    = var.cluster_name
  namespace       = "monitoring"
  service_account = "kube-prometheus-stack-prometheus"
  role_arn        = aws_iam_role.amp_remote_write.arn
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_version

  values = [
    yamlencode({
      # No built-in Grafana or local long-term storage — AMG + AMP are the source of truth.
      grafana = { enabled = false }
      prometheus = {
        prometheusSpec = {
          retention = "6h" # local buffer only, in case remote_write briefly falls behind
          remoteWrite = [
            {
              url = "https://aps-workspaces.${var.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.this.id}/api/v1/remote_write"
              sigv4 = {
                region = var.region
              }
              queueConfig = {
                maxSamplesPerSend = 1000
                maxShards         = 30
              }
            }
          ]
          tolerations = [
            { key = "node-role", operator = "Equal", value = "core", effect = "NoSchedule" }
          ]
          nodeSelector = { "node-role" = "core" }
          replicas     = 2
        }
      }
      alertmanager = {
        alertmanagerSpec = {
          tolerations  = [{ key = "node-role", operator = "Equal", value = "core", effect = "NoSchedule" }]
          nodeSelector = { "node-role" = "core" }
          replicas     = 2
        }
      }
    })
  ]

  depends_on = [aws_eks_pod_identity_association.amp_remote_write]
}
