# Production EKS Platform

A battle-tested, from-scratch Amazon EKS platform built entirely with Terraform: multi-AZ HA by default, multi-region DR (active-passive fully built, active-active documented as an extension), Karpenter-based autoscaling (with EKS Auto Mode documented as an alternative compute model), Istio service mesh for canary/blue-green traffic shifting, ArgoCD + Argo Rollouts for GitOps and progressive delivery, KMS envelope encryption, full control-plane logging, and managed observability.

## Start here

**Installing this for the first time? Skip straight to [docs/installation-guide.md](docs/installation-guide.md)** — it's the complete, ordered, copy-pasteable sequence from an empty AWS account to a running platform. Everything below is architectural background, not a setup sequence.

| If you want to... | Read |
|---|---|
| **Install this platform step by step** | **[docs/installation-guide.md](docs/installation-guide.md)** |
| Understand the whole system in one pass | [docs/architecture/00-overview.md](docs/architecture/00-overview.md) |
| Compare Karpenter vs EKS Auto Mode | [docs/architecture/01-compute-karpenter-vs-automode.md](docs/architecture/01-compute-karpenter-vs-automode.md) |
| See the VPC layout and how DNS resolves inside the cluster | [docs/architecture/02-networking-vpc.md](docs/architecture/02-networking-vpc.md) |
| Understand secrets encryption, Pod Identity vs IRSA | [docs/architecture/03-security-iam-encryption.md](docs/architecture/03-security-iam-encryption.md) |
| See how a request flows through Istio (mTLS, sidecars) | [docs/architecture/04-service-mesh-istio.md](docs/architecture/04-service-mesh-istio.md) |
| Understand the Terraform/GitOps split | [docs/architecture/05-gitops-argocd-rollouts.md](docs/architecture/05-gitops-argocd-rollouts.md) |
| See logging/metrics flow | [docs/architecture/06-observability-logging.md](docs/architecture/06-observability-logging.md) |
| Trace a client request end-to-end (DNS → ALB/Istio → pod) | [docs/architecture/07-ingress-dns.md](docs/architecture/07-ingress-dns.md) |
| Run canary or blue-green deployments | [docs/architecture/08-progressive-delivery-canary-bluegreen.md](docs/architecture/08-progressive-delivery-canary-bluegreen.md) |
| Plan for AZ failure (single region) | [docs/dr-ha/01-single-region-multi-az-ha.md](docs/dr-ha/01-single-region-multi-az-ha.md) |
| Plan for a full region loss (warm standby) | [docs/dr-ha/02-multi-region-active-passive-dr.md](docs/dr-ha/02-multi-region-active-passive-dr.md) |
| Go active-active across regions | [docs/dr-ha/03-multi-region-active-active-dr.md](docs/dr-ha/03-multi-region-active-active-dr.md) |
| Actually execute a DR failover | [docs/runbooks/dr-failover-runbook.md](docs/runbooks/dr-failover-runbook.md) |

## Repository layout

```
terraform/
  modules/        # reusable building blocks (vpc, eks-cluster, karpenter, istio, argocd-bootstrap, ...)
  live/            # environment stacks that call the modules (us-east-1/staging, us-east-1/prod, us-west-2/dr-prod)
kubernetes/
  bootstrap/       # ArgoCD install values (Terraform-applied)
  apps/            # ArgoCD-managed: app-of-apps root + example workload (Rollout, VirtualService)
docs/
  architecture/    # how the platform works, with Mermaid diagrams
  dr-ha/           # HA and DR strategies, three tiers
  runbooks/        # step-by-step operational procedures
scripts/           # operational helpers (see below)
```

The three scripts:

- [`scripts/bootstrap.sh`](scripts/bootstrap.sh) — one-time S3 state-backend creation (step 1 of the install guide).
- [`scripts/kubeconfig.sh`](scripts/kubeconfig.sh) — `kubeconfig.sh <staging|prod|dr-prod>` switches your kubectl context to the right cluster/region and sanity-checks it with `kubectl get nodes`.
- [`scripts/dr-failover.sh`](scripts/dr-failover.sh) — interactive checklist-runner for the first half of [docs/runbooks/dr-failover-runbook.md](docs/runbooks/dr-failover-runbook.md); read the runbook before using it.

## Terraform / GitOps ownership boundary

Terraform provisions everything through **"a working cluster with ArgoCD installed and a root Application pointing at this repo."** That includes: VPC, EKS control plane (encrypted, fully logged), Karpenter, core EKS addons, Istio control plane, platform addons (ALB Controller, external-dns, cert-manager, external-secrets, Fluent Bit), observability (AMP/AMG), and the ArgoCD installation itself plus its root `Application`.

**ArgoCD then owns the workload layer**: application Deployments/Rollouts, per-app VirtualServices/DestinationRules, and anything under `kubernetes/apps/`. Terraform never reconciles workload manifests, and ArgoCD never touches cluster infrastructure. See [docs/architecture/05-gitops-argocd-rollouts.md](docs/architecture/05-gitops-argocd-rollouts.md) for the full rationale and diagram.

## Getting started (first-time bootstrap)

Full instructions, including every placeholder value you need to replace first (account IDs, domain, repo URL) and a verification checklist for each step, are in **[docs/installation-guide.md](docs/installation-guide.md)**. The short version, once placeholders are replaced:

```bash
# 1. One-time, manual, per region: create the S3 state backend (not itself remote-stated)
cd terraform/modules/state-backend-bootstrap
terraform init && terraform apply -var="region=us-east-1"
terraform apply -var="region=us-west-2"

# 2. terraform/live/global (first pass) → staging → prod → dr-prod → terraform/live/global (second pass)
# See docs/installation-guide.md for the full sequence and verification steps at each stage.
```

[scripts/bootstrap.sh](scripts/bootstrap.sh) automates step 1. Do not run `terraform apply` against a real account before reading [docs/installation-guide.md](docs/installation-guide.md) and the relevant `docs/architecture/*.md` pages.

## Module and tool versions

| Component | Version / source |
|---|---|
| `terraform-aws-modules/vpc/aws` | ~> 6.0 |
| `terraform-aws-modules/eks/aws` | ~> 21.0 (includes the `karpenter` submodule) |
| `aws-ia/eks-blueprints-addons/aws` | ~> 1.18 |
| Karpenter | v1.x (stable `karpenter.sh/v1` API) |
| Istio | 1.30.x, sidecar injection mode |
| ArgoCD + Argo Rollouts | latest stable Helm charts, Rollouts Istio traffic-router plugin |
| Terraform state backend | S3 with native locking (`use_lockfile`), no DynamoDB table |

AWS App Mesh was deliberately **not** used — it is end-of-life, shutting down September 30, 2026. See [docs/architecture/04-service-mesh-istio.md](docs/architecture/04-service-mesh-istio.md) for the comparison.
