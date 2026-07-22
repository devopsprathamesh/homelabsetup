# EKS-managed addons for the standard (non-Auto-Mode) compute path. Under EKS Auto Mode
# these are ALL redundant/blocked (Auto Mode ships its own pod networking, kube-proxy-less
# service networking, DNS, and EBS handling) — see
# docs/architecture/01-compute-karpenter-vs-automode.md.
#
# Ordering matters here:
#   1. pod-identity-agent first — every other controller's IAM (Karpenter, EBS CSI, LB
#      Controller, external-dns, ...) depends on the Pod Identity webhook being live.
#   2. vpc-cni / kube-proxy — core pod networking.
#   3. coredns — needs at least one node with working pod networking to schedule onto.
#   4. aws-ebs-csi-driver — needs its Pod Identity association in place before pods using
#      PVCs can mount volumes.

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = var.cluster_name
  addon_name    = "eks-pod-identity-agent"
  addon_version = var.pod_identity_agent_version
  resolve_conflicts_on_update = "OVERWRITE"
  tags          = var.tags
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = var.cluster_name
  addon_name    = "vpc-cni"
  addon_version = var.vpc_cni_version
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = {
      # Prefix delegation raises pod-per-node density substantially on Nitro instances —
      # avoids running out of IPs long before you run out of CPU/memory on larger nodes.
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })

  tags = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = var.cluster_name
  addon_name    = "kube-proxy"
  addon_version = var.kube_proxy_version
  resolve_conflicts_on_update = "OVERWRITE"
  tags          = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = var.cluster_name
  addon_name    = "coredns"
  addon_version = var.coredns_version
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    replicaCount = var.coredns_replica_count
    # Spread CoreDNS across AZs/nodes so an AZ loss never takes cluster DNS down with it.
    topologySpreadConstraints = [
      {
        maxSkew           = 1
        topologyKey       = "topology.kubernetes.io/zone"
        whenUnsatisfiable = "ScheduleAnyway"
        labelSelector = {
          matchLabels = { "k8s-app" = "kube-dns" }
        }
      }
    ]
    tolerations = [
      { key = "node-role", operator = "Equal", value = "core", effect = "NoSchedule" }
    ]
    nodeSelector = { "node-role" = "core" }
  })

  depends_on = [aws_eks_addon.vpc_cni, aws_eks_addon.kube_proxy]
  tags       = var.tags
}

# --- EBS CSI driver: IAM via Pod Identity (not IRSA) ---

resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name  = var.cluster_name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = var.ebs_csi_version
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    controller = {
      tolerations = [
        { key = "node-role", operator = "Equal", value = "core", effect = "NoSchedule" }
      ]
      nodeSelector = { "node-role" = "core" }
    }
  })

  depends_on = [aws_eks_pod_identity_association.ebs_csi]
  tags       = var.tags
}

# The default (gp3) StorageClass is created in terraform/modules/platform-addons since it
# requires a Kubernetes API connection rather than just the AWS API used in this module.
