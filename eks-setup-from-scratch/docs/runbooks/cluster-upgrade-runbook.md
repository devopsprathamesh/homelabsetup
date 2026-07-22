# Runbook: EKS Cluster Version Upgrade

EKS control-plane and data-plane versions can skip at most one minor version per upgrade — never jump directly from e.g. 1.30 to 1.32. Do this in staging first, always.

## 1. Pre-flight checks

```bash
# Check for deprecated/removed API usage before upgrading
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis

# Or use the AWS-provided tool
eksup analyze --cluster eks-platform-prod --region us-east-1
```

Review the [EKS release notes](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html) for the target version's removed APIs, and check every Helm chart pinned in `terraform/modules/*/main.tf` (Karpenter, Istio, ArgoCD, aws-ia/eks-blueprints-addons) for compatibility with the target Kubernetes version.

## 2. Upgrade the control plane

```bash
cd terraform/live/us-east-1/staging
```

Edit `kubernetes_version` in `main.tf`'s `eks_cluster` module call (e.g. `"1.32"` → `"1.33"`), then:

```bash
terraform plan   # confirm ONLY the control plane version is changing
terraform apply
```

This is a **~20-30 minute AWS-managed operation** with no downtime to the API server (multi-AZ control plane), but new API server capabilities/removals take effect immediately on completion.

## 3. Upgrade EKS-managed addons

Managed addons ([`terraform/modules/eks-core-addons`](../../terraform/modules/eks-core-addons)) should track the new control-plane version. Check available versions and bump the version variables:

```bash
aws eks describe-addon-versions --addon-name vpc-cni --kubernetes-version 1.33
```

Apply the same way — `terraform plan` / `apply` in the affected `live/*` stack.

## 4. Upgrade the core node group AMI

The managed node group in [`terraform/modules/eks-cluster`](../../terraform/modules/eks-cluster) uses the latest AMI release for its Kubernetes version automatically on node replacement, but existing nodes need an explicit rolling update:

```bash
aws eks update-nodegroup-version --cluster-name eks-platform-staging --nodegroup-name core
```

This drains and replaces core nodes one at a time, respecting pod disruption budgets — confirm ArgoCD, Istiod, and Karpenter all have `PodDisruptionBudget`s with `minAvailable` set before running this, or add them first.

## 5. Karpenter-provisioned nodes

Karpenter doesn't need an explicit upgrade step for node AMIs — its `EC2NodeClass` uses `amiFamily: Bottlerocket`, which resolves to the latest compatible AMI at *launch* time. To roll existing Karpenter nodes onto the new version's AMI without waiting for natural consolidation:

```bash
kubectl annotate nodeclaim -l karpenter.sh/nodepool=default karpenter.sh/force-drift=true
```

(Or just wait — Karpenter's drift detection will replace them naturally once the AMI they're running no longer matches the current `EC2NodeClass` resolution.)

## 6. Verify

```bash
kubectl get nodes -o wide   # confirm all nodes report the new kubelet version
kubectl get pods -A | grep -v Running   # nothing should be stuck
kubectl argo rollouts list rollouts -A   # confirm no rollout is stuck mid-step
```

Check Grafana for any error-rate anomaly correlated with the upgrade window.

## 7. Promote to prod

Only after staging has run clean on the new version for a reasonable soak period (at minimum, through one full business day's traffic pattern) — repeat steps 2-6 against `terraform/live/us-east-1/prod`, then `terraform/live/us-west-2/dr-prod`.
