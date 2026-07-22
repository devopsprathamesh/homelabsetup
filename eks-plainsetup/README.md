# eks-plainsetup

A single-cluster EKS build using **raw AWS CLI** commands only — no `eksctl`, no Terraform. Meant as the minimal, see-every-API-call counterpart to [`../eks-setup-from-scratch`](../eks-setup-from-scratch), which is the Terraform + GitOps multi-region version of this platform.

Start here: [`docs/installation-guide.md`](docs/installation-guide.md) — covers prerequisites, VPC networking, the EKS control plane and node group, the four core add-ons (VPC CNI, kube-proxy, CoreDNS, EBS CSI Driver) wired up via **EKS Pod Identity**, three essential extras (metrics-server, Cluster Autoscaler, AWS Load Balancer Controller), a post-install validation checklist, troubleshooting, and teardown.
