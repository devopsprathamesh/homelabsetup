# 01. Prerequisites

## Tools

| Tool | Minimum version | Why |
|---|---|---|
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | v2.15+ | `aws eks create-pod-identity-association` and the `AL2023` node AMI types require a recent v2 build |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | matching your cluster's k8s version | |
| [jq](https://jqlang.github.io/jq/download/) | any recent | parsing CLI JSON output into shell variables throughout these docs |
| [helm](https://helm.sh/docs/intro/install/) | 3.x | used for the AWS Load Balancer Controller ([07](07-metrics-server-and-alb-ingress.md)) and Karpenter ([06](06-node-autoscaling.md), if you choose that path) |
| `curl` | — | downloading IAM policy JSON and CRDs from upstream GitHub repos |

Verify each tool is present and new enough before starting:

```bash
aws --version          # expect aws-cli/2.15+ 
kubectl version --client
jq --version
helm version --short   # expect v3.x
curl --version | head -1
```

## AWS account

- An IAM principal with permissions to create VPCs/subnets/route tables/NAT gateways, IAM roles/policies, EKS clusters/nodegroups/addons/pod-identity-associations, and EC2 instances/launch templates. `AdministratorAccess` is the pragmatic starting point for a first build.
- Enough EIP quota for at least one NAT Gateway (default account quota is 5, this build uses 1).
- If you plan to use **Karpenter** (see [06-node-autoscaling.md](06-node-autoscaling.md)) rather than Cluster Autoscaler, no extra account setup is needed now — its IAM role and instance profile are created in that doc.

Confirm your credentials work and you're in the account/principal you think
you are — every doc after this creates billable resources under whatever
this returns:

```bash
aws sts get-caller-identity
# expect your Account id and an Arn for the intended user/role — if this
# errors, fix `aws configure` / SSO login before going any further
```

## Export environment variables

Every doc from here on references these — export them once per shell session, and re-export the same values if you come back in a new shell:

```bash
export AWS_REGION=us-east-1
export CLUSTER_NAME=plain-eks-cluster
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Confirm the k8s version you pick is still supported before hardcoding it:
aws eks describe-addon-versions --kubernetes-version 1.32 --query 'addons[0].addonName' >/dev/null \
  && echo "1.32 is queryable" || echo "check https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html for current supported versions"
export K8S_VERSION=1.32

export VPC_CIDR=10.20.0.0/16
mkdir -p ~/eks-plainsetup-tmp && cd ~/eks-plainsetup-tmp   # scratch dir every doc writes policy/trust JSON files into
```

Next: [02-networking-vpc.md](02-networking-vpc.md)
