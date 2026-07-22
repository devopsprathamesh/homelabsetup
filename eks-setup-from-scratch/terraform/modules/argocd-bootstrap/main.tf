# The Terraform -> GitOps handoff point (see docs/architecture/05-gitops-argocd-rollouts.md).
#
# Terraform-owned: the ArgoCD Helm release itself, and the Argo Rollouts controller (a
# cluster-wide controller + CRDs, treated as platform infrastructure like Istio — not a
# workload). GOTCHA avoided here deliberately: the ArgoCD root Application is scoped to
# manage `kubernetes/apps/` in this repo and explicitly does NOT include the `argocd`
# namespace/release itself, so ArgoCD never tries to reconcile (and fight Terraform over)
# its own installation.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  values = [
    yamlencode({
      global = {
        tolerations  = [{ key = "node-role", operator = "Equal", value = "core", effect = "NoSchedule" }]
        nodeSelector = { "node-role" = "core" }
      }
      redis-ha = { enabled = true }
      controller = {
        replicas = 1 # application-controller is a StatefulSet, single logical shard by design
      }
      server = {
        replicas = 2
        ingress  = { enabled = false } # exposed via Istio Gateway/VirtualService instead, see kubernetes/istio/
      }
      repoServer = {
        replicas = 2
      }
      applicationSet = {
        replicas = 2
      }
      configs = {
        params = {
          "server.insecure" = true # TLS terminated at the Istio ingress gateway
        }
      }
    })
  ]
}

resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  namespace        = "argo-rollouts"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  version          = var.argo_rollouts_chart_version

  values = [
    yamlencode({
      controller = {
        replicas     = 2
        tolerations  = [{ key = "node-role", operator = "Equal", value = "core", effect = "NoSchedule" }]
        nodeSelector = { "node-role" = "core" }
      }
      # Enables the built-in Istio traffic-management integration so a Rollout can
      # directly manipulate VirtualService weights / DestinationRule subsets.
      dashboard = { enabled = true }
    })
  ]
}

# --- Root Application (app-of-apps): the one and only Terraform-created Application ---
resource "kubectl_manifest" "root_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = "argocd"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_target_revision
        path           = var.gitops_root_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })

  depends_on = [helm_release.argocd]
}
