# eks-plainsetup

A single-cluster EKS build using **raw AWS CLI** commands only — no `eksctl`, no Terraform. Meant as the minimal, see-every-API-call counterpart to [`../eks-setup-from-scratch`](../eks-setup-from-scratch), which is the Terraform + GitOps multi-region version of this platform.

## Start here

**Building this for the first time? Start at [docs/00-overview.md](docs/00-overview.md)** — it has the full build-sequence flowchart and links every doc below in order.

| If you want to... | Read |
|---|---|
| See the full build sequence and doc map | [docs/00-overview.md](docs/00-overview.md) |
| Install tools and set up your shell | [docs/01-prerequisites.md](docs/01-prerequisites.md) |
| Build the VPC | [docs/02-networking-vpc.md](docs/02-networking-vpc.md) |
| Create the EKS control plane | [docs/03-cluster-control-plane.md](docs/03-cluster-control-plane.md) |
| Create the managed node group | [docs/04-node-group.md](docs/04-node-group.md) |
| Install VPC CNI, kube-proxy, CoreDNS, EBS CSI (via Pod Identity) | [docs/05-pod-identity-core-addons.md](docs/05-pod-identity-core-addons.md) |
| Choose and install Cluster Autoscaler or Karpenter | [docs/06-node-autoscaling.md](docs/06-node-autoscaling.md) |
| Install metrics-server and the AWS Load Balancer Controller | [docs/07-metrics-server-and-alb-ingress.md](docs/07-metrics-server-and-alb-ingress.md) |
| Verify the whole build actually works | [docs/08-post-install-validation.md](docs/08-post-install-validation.md) |
| Diagnose a failure | [docs/09-troubleshooting.md](docs/09-troubleshooting.md) |
| Tear the whole thing down | [docs/10-teardown.md](docs/10-teardown.md) |

## Scope

One VPC, one EKS cluster, one managed node group, the four core add-ons (VPC CNI, kube-proxy, CoreDNS, EBS CSI Driver), node autoscaling (Cluster Autoscaler **or** Karpenter — [docs/06-node-autoscaling.md](docs/06-node-autoscaling.md) covers both as separate options), and two essential extras (metrics-server, AWS Load Balancer Controller). Every add-on/controller gets its AWS permissions via **EKS Pod Identity**, not IRSA/OIDC — no OIDC provider is created for this cluster.
