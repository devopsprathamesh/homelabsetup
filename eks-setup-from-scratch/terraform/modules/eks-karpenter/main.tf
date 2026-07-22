# Karpenter v1 (stable karpenter.sh/v1 + karpenter.k8s.aws/v1 API). Controller IAM uses
# Pod Identity (NOT IRSA) — Karpenter runs as a normal pod on the "core" managed node
# group, so Pod Identity applies cleanly; IRSA is only still needed for Fargate, which
# this platform doesn't use. GOTCHA: the eks-core-addons module's pod-identity-agent
# addon must be applied before this module — enforced via depends_on below.

terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
  }
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  # Ensures the Pod Identity Agent addon exists before Karpenter's controller Pod
  # Identity association is created; pass eks-core-addons.pod_identity_agent_ready here.
  depends_on = [var.pod_identity_agent_dependency]

  cluster_name = var.cluster_name

  # Pod Identity, not IRSA.
  enable_irsa                    = false
  enable_pod_identity            = true
  create_pod_identity_association = true

  # Karpenter needs to terminate/create instances tagged with the cluster's discovery
  # tag and manage an interruption-queue for spot rebalance/health events.
  enable_spot_termination = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "kube-system"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_chart_version
  wait             = true

  values = [
    yamlencode({
      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = var.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      serviceAccount = {
        name = "karpenter"
      }
      # Karpenter itself runs on the tainted "core" node group so it's never at risk
      # of being scheduled onto (and evicted from) a node it manages.
      tolerations = [
        { key = "node-role", operator = "Equal", value = "core", effect = "NoSchedule" }
      ]
      nodeSelector = { "node-role" = "core" }
      replicas     = var.karpenter_replicas
      controller = {
        resources = {
          requests = { cpu = "1", memory = "1Gi" }
          limits   = { memory = "1Gi" }
        }
      }
    })
  ]

  depends_on = [module.karpenter]
}

# --- Default EC2NodeClass: how Karpenter launches instances ---
resource "kubectl_manifest" "default_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      amiFamily = "Bottlerocket"
      role      = module.karpenter.node_iam_role_name
      subnetSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      securityGroupSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      # EBS root volume — gp3 for cost/perf balance.
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "50Gi"
            volumeType          = "gp3"
            encrypted           = true
            deleteOnTermination = true
          }
        }
      ]
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 2 # IMDSv2 only, hop-limited to block pod-level access
        httpTokens              = "required"
      }
      tags = var.tags
    }
  })

  depends_on = [helm_release.karpenter]
}

# --- Default NodePool: general-purpose, spot-first, consolidated aggressively ---
resource "kubectl_manifest" "default_node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "default" }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["4"] },
          ]
          # Give Envoy/Istio sidecars and app containers enough grace to drain
          # in-flight connections before Karpenter forcibly terminates the node.
          terminationGracePeriod = "5m"
        }
      }
      limits = {
        cpu    = var.nodepool_cpu_limit
        memory = var.nodepool_memory_limit
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
        budgets = [
          # Never disrupt more than 1 node at a time, and never during business-critical
          # hours unless the node is completely empty — tune per environment.
          { nodes = "1" },
          { nodes = "0", schedule = "0 8 * * mon-fri", duration = "10h" },
        ]
      }
      weight = 10
    }
  })

  depends_on = [kubectl_manifest.default_node_class]
}
