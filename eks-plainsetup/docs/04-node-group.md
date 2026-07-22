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

If you plan to use **Karpenter** for autoscaling instead of Cluster Autoscaler (see [06-node-autoscaling.md](06-node-autoscaling.md)), this node group still matters — it hosts your baseline/system workloads (CoreDNS, the ALB controller, Karpenter's own controller pods), while Karpenter provisions additional capacity on top for everything else. Don't skip it.

## Resume variables (new shell)

```bash
NODE_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-node-role --query 'Role.Arn' --output text)
```

Next: [05-pod-identity-core-addons.md](05-pod-identity-core-addons.md)
