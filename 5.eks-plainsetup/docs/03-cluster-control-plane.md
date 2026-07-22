# 03. Cluster IAM Role + EKS Control Plane

Assumes [02-networking-vpc.md](02-networking-vpc.md) is done and `$VPC_ID`, `${PUBLIC_SUBNET_IDS[@]}`, `${PRIVATE_SUBNET_IDS[@]}` are set in this shell (see that doc's "Resume variables" if you're in a new shell).

## Cluster IAM role

```bash
cd ~/eks-plainsetup-tmp

cat > cluster-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "eks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role --role-name ${CLUSTER_NAME}-cluster-role \
  --assume-role-policy-document file://cluster-trust-policy.json
aws iam attach-role-policy --role-name ${CLUSTER_NAME}-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
CLUSTER_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-cluster-role --query 'Role.Arn' --output text)
```

## Create the cluster

```bash
ALL_SUBNETS="${PUBLIC_SUBNET_IDS[@]} ${PRIVATE_SUBNET_IDS[@]}"
aws eks create-cluster \
  --name $CLUSTER_NAME \
  --kubernetes-version $K8S_VERSION \
  --role-arn $CLUSTER_ROLE_ARN \
  --resources-vpc-config subnetIds=$(IFS=,; echo "${ALL_SUBNETS// /,}"),endpointPublicAccess=true,endpointPrivateAccess=true \
  --tags Name=$CLUSTER_NAME

aws eks wait cluster-active --name $CLUSTER_NAME   # takes ~10 minutes
```

## Configure kubectl

```bash
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
kubectl get svc   # should return the default `kubernetes` service — confirms auth + connectivity
```

## Resume variables (new shell)

```bash
CLUSTER_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-cluster-role --query 'Role.Arn' --output text)
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
```

Next: [04-node-group.md](04-node-group.md)
