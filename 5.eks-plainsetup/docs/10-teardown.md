# 10. Tearing Everything Down

Destroy in **reverse** order — controllers that hold live AWS resources (ALBs, EC2 instances) must go before the node group/cluster, and the NAT Gateway/EIP must go before the VPC will delete cleanly.

## 1. Uninstall controllers

```bash
helm uninstall aws-load-balancer-controller -n kube-system
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Whichever you installed in 06:
# Cluster Autoscaler:
kubectl delete namespace cluster-autoscaler
# Karpenter — delete NodePool first so it deprovisions its nodes cleanly, then the controller:
kubectl delete nodepool default
kubectl delete ec2nodeclass default
helm uninstall karpenter -n kube-system
```

## 2. Remove Pod Identity associations

```bash
for ASSOC_ID in $(aws eks list-pod-identity-associations --cluster-name $CLUSTER_NAME --query 'associations[].associationId' --output text); do
  aws eks delete-pod-identity-association --cluster-name $CLUSTER_NAME --association-id $ASSOC_ID
done
```

## 3. Delete the node group and cluster

```bash
aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name core-ng
aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name core-ng

aws eks delete-cluster --name $CLUSTER_NAME
aws eks wait cluster-deleted --name $CLUSTER_NAME
```

## 4. Delete Karpenter's SQS queue + EventBridge rules (skip if you used Cluster Autoscaler)

```bash
for RULE in SpotInterruption RebalanceRecommendation InstanceStateChange ScheduledChange; do
  aws events remove-targets --rule "${CLUSTER_NAME}-karpenter-${RULE}" --ids 1
  aws events delete-rule --name "${CLUSTER_NAME}-karpenter-${RULE}"
done
aws sqs delete-queue --queue-url $QUEUE_URL
```

## 5. Delete IAM roles and policies

```bash
for ROLE in cluster-role node-role vpc-cni-role ebs-csi-role cluster-autoscaler-role karpenter-controller-role alb-controller-role; do
  ROLE_NAME=${CLUSTER_NAME}-${ROLE}
  for POLICY_ARN in $(aws iam list-attached-role-policies --role-name $ROLE_NAME --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN
  done
  aws iam delete-role --role-name $ROLE_NAME 2>/dev/null
done

for POLICY in cluster-autoscaler-policy karpenter-controller-policy alb-controller-policy; do
  aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${CLUSTER_NAME}-${POLICY} 2>/dev/null
done
```

Only some of these roles/policies will exist depending on whether you picked Cluster Autoscaler or Karpenter in [06](06-node-autoscaling.md) — the `2>/dev/null` guards let you run the whole loop unconditionally.

## 6. Delete networking

```bash
aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW_ID
aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT_GW_ID
aws ec2 release-address --allocation-id $EIP_ALLOC

for s in "${PUBLIC_SUBNET_IDS[@]}" "${PRIVATE_SUBNET_IDS[@]}"; do aws ec2 delete-subnet --subnet-id $s; done
aws ec2 delete-route-table --route-table-id $PUB_RT_ID
aws ec2 delete-route-table --route-table-id $PRIV_RT_ID
aws ec2 detach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
aws ec2 delete-vpc --vpc-id $VPC_ID
```

NAT Gateway deletion takes a few minutes — the EIP release and VPC delete will fail with a dependency error if you race ahead of `nat-gateway-deleted`.

If you're in a fresh shell and don't have `$PUB_RT_ID`/`$PRIV_RT_ID` set, look them up first: `aws ec2 describe-route-tables --filters Name=tag:Name,Values="${CLUSTER_NAME}-*-rt" --query 'RouteTables[].RouteTableId'`.
