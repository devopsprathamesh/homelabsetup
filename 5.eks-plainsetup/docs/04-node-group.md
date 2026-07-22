# 04. Node IAM Role + Managed Node Group

Assumes [03-cluster-control-plane.md](03-cluster-control-plane.md) is done — cluster is `ACTIVE` and `kubectl` is configured.

## Node IAM role

```bash
cd ~/eks-plainsetup-tmp

cat > node-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role --role-name ${CLUSTER_NAME}-node-role \
  --assume-role-policy-document file://node-trust-policy.json
for POLICY in AmazonEKSWorkerNodePolicy AmazonEC2ContainerRegistryReadOnly AmazonSSMManagedInstanceCore; do
  aws iam attach-role-policy --role-name ${CLUSTER_NAME}-node-role \
    --policy-arn arn:aws:iam::aws:policy/$POLICY
done
NODE_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-node-role --query 'Role.Arn' --output text)
```

`AmazonEKS_CNI_Policy` is deliberately **not** attached here — the VPC CNI gets its AWS permissions via Pod Identity in [05-pod-identity-core-addons.md](05-pod-identity-core-addons.md) instead, so the node role stays minimal. `AmazonSSMManagedInstanceCore` gives you Session Manager shell access to nodes without opening SSH.

## Create the managed node group

```bash
aws eks create-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name core-ng \
  --node-role $NODE_ROLE_ARN \
  --subnets ${PRIVATE_SUBNET_IDS[@]} \
  --instance-types t3.medium \
  --ami-type AL2023_x86_64_STANDARD \
  --disk-size 30 \
  --scaling-config minSize=2,maxSize=6,desiredSize=2 \
  --labels role=core

aws eks wait nodegroup-active --cluster-name $CLUSTER_NAME --nodegroup-name core-ng   # ~3-5 minutes

kubectl get nodes -o wide   # 2 nodes, Ready
```

## What `create-nodegroup` actually does under the hood

A "managed node group" is EKS orchestrating plain EC2 primitives on your
behalf — all of it visible in your account, unlike the control plane:

```mermaid
sequenceDiagram
    participant You as aws eks create-nodegroup
    participant EKS as EKS service
    participant EC2 as EC2 (your account)
    participant Node as new instance
    participant API as EKS apiserver
    You->>EKS: create-nodegroup (role, subnets, scaling config)
    EKS->>EC2: create launch template<br/>(EKS-optimized AL2023 AMI + user data)
    EKS->>EC2: create Auto Scaling Group<br/>(min 2 / max 6 / desired 2, private subnets)
    EC2->>Node: launch instances
    Node->>Node: cloud-init runs nodeadm: reads cluster name,<br/>endpoint, CA from user data; configures<br/>containerd + kubelet
    Node->>API: kubelet connects (private endpoint),<br/>authenticates via the NODE ROLE's<br/>instance credentials
    API->>API: node role is pre-authorized by EKS<br/>(access entry) → kubelet may register
    Node->>API: register Node object, report Ready<br/>(Ready requires the CNI — see doc 05)
```

What each attached policy is for, mapped to that flow:
`AmazonEKSWorkerNodePolicy` lets the node describe EKS/EC2 resources during
bootstrap; `AmazonEC2ContainerRegistryReadOnly` lets containerd pull images
from ECR (where all EKS system images live); `AmazonSSMManagedInstanceCore`
is purely for your shell access. The kubelet's *Kubernetes* identity comes
from the node role too — EKS automatically creates an access entry mapping
it into the `system:nodes` group, which is the managed equivalent of the
kubelet kubeconfigs you hand-built in the hard way.

Because it's just an ASG underneath, node replacement on failure, rolling
AMI upgrades, and graceful drain-on-scale-down are EKS-driven ASG
operations — you'll see the ASG itself in the EC2 console named
`eks-core-ng-...`. (Don't edit that ASG directly; EKS owns it and will
fight you.)

If you plan to use **Karpenter** for autoscaling instead of Cluster Autoscaler (see [06-node-autoscaling.md](06-node-autoscaling.md)), this node group still matters — it hosts your baseline/system workloads (CoreDNS, the ALB controller, Karpenter's own controller pods), while Karpenter provisions additional capacity on top for everything else. Don't skip it.

## Resume variables (new shell)

```bash
NODE_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-node-role --query 'Role.Arn' --output text)
```

Next: [05-pod-identity-core-addons.md](05-pod-identity-core-addons.md)
