# Istio 1.30.x, sidecar injection mode (not ambient — see docs/architecture/04-service-mesh-istio.md
# for why). Runs on the "core" node group alongside other cluster-critical controllers.
#
# GOTCHA (documented, not silently worked around): Karpenter consolidation can terminate a
# node while an Envoy sidecar still has in-flight connections. We mitigate this two ways:
#   1. ENABLE_NATIVE_SIDECARS — uses Kubernetes native sidecar containers (initContainers
#      with restartPolicy: Always), which get a SIGTERM only after the main app container
#      exits, giving Envoy time to drain.
#   2. Karpenter's NodePool terminationGracePeriod (see eks-karpenter module) is set to 5m
#      to give that drain sequence room to complete.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
  }
}

resource "kubernetes_namespace_v1" "istio_system" {
  metadata {
    name   = "istio-system"
    labels = { "topology.istio.io/network" = var.network_name }
  }
}

resource "kubernetes_namespace_v1" "istio_ingress" {
  metadata {
    name = "istio-ingress"
  }
}

resource "helm_release" "istio_base" {
  name       = "istio-base"
  namespace  = kubernetes_namespace_v1.istio_system.metadata[0].name
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  version    = var.istio_version
  wait       = true
}

resource "helm_release" "istiod" {
  name       = "istiod"
  namespace  = kubernetes_namespace_v1.istio_system.metadata[0].name
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = var.istio_version
  wait       = true

  values = [
    yamlencode({
      pilot = {
        replicaCount = var.istiod_replicas
        autoscaleMin = var.istiod_replicas
        resources = {
          requests = { cpu = "500m", memory = "2Gi" }
        }
        tolerations = [
          { key = "node-role", operator = "Equal", value = "core", effect = "NoSchedule" }
        ]
        nodeSelector = { "node-role" = "core" }
        env = {
          PILOT_ENABLE_ALPHA_GATEWAY_API = "false"
        }
      }
      meshConfig = {
        # Strict mTLS mesh-wide by default; PeerAuthentication below enforces it.
        defaultConfig = {
          holdApplicationUntilProxyStarts = true
        }
        accessLogFile = "/dev/stdout"
      }
      global = {
        proxy = {
          resources = {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { memory = "1Gi" }
          }
        }
        # Native sidecars: see module header comment.
        env = {
          ENABLE_NATIVE_SIDECARS = "true"
        }
      }
    })
  ]

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingressgateway" {
  name       = "istio-ingressgateway"
  namespace  = kubernetes_namespace_v1.istio_ingress.metadata[0].name
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  version    = var.istio_version
  wait       = true

  values = [
    yamlencode({
      replicaCount = var.ingressgateway_replicas
      autoscaling = {
        enabled     = true
        minReplicas = var.ingressgateway_replicas
        maxReplicas = var.ingressgateway_max_replicas
      }
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"                              = "external"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                   = "ip"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"                            = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
          # Fixed, predictable name so this module can look the NLB back up via the aws_lb
          # data source below (used for Route53 failover records — see outputs.tf).
          "service.beta.kubernetes.io/aws-load-balancer-name" = var.ingressgateway_lb_name
        }
      }
      resources = {
        requests = { cpu = "200m", memory = "256Mi" }
      }
    })
  ]

  depends_on = [helm_release.istiod]
}

# Looked up after the fact (rather than managed as an aws_lb resource) because the LB
# controller, not Terraform, creates it in response to the Kubernetes Service object above.
data "aws_lb" "ingress" {
  name       = var.ingressgateway_lb_name
  depends_on = [helm_release.istio_ingressgateway]
}

# Mesh-wide strict mTLS — every pod-to-pod call inside the mesh is mutually authenticated
# and encrypted by default; workloads opt out per-namespace only with explicit justification.
resource "kubernetes_manifest" "strict_mtls" {
  manifest = {
    apiVersion = "security.istio.io/v1"
    kind       = "PeerAuthentication"
    metadata = {
      name      = "default"
      namespace = kubernetes_namespace_v1.istio_system.metadata[0].name
    }
    spec = {
      mtls = { mode = "STRICT" }
    }
  }

  depends_on = [helm_release.istiod]
}
