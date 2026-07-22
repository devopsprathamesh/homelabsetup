# 07. metrics-server + AWS Load Balancer Controller

Assumes [06-node-autoscaling.md](06-node-autoscaling.md) is done (either option).

## metrics-server

No IAM needed — it only talks to the kubelet API inside the cluster.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl wait --for=condition=available --timeout=120s deployment/metrics-server -n kube-system
kubectl top nodes   # should return CPU/memory, not an error
```

## AWS Load Balancer Controller (via Pod Identity)

Provisions ALBs/NLBs for `Ingress` and `Service type=LoadBalancer` objects. Relies on the `kubernetes.io/role/elb` / `internal-elb` subnet tags from [02-networking-vpc.md](02-networking-vpc.md).

```bash
cd ~/eks-plainsetup-tmp

curl -o alb-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.9.2/docs/install/iam_policy.json
aws iam create-policy --policy-name ${CLUSTER_NAME}-alb-controller-policy --policy-document file://alb-iam-policy.json
aws iam create-role --role-name ${CLUSTER_NAME}-alb-controller-role \
  --assume-role-policy-document file://pod-identity-trust-policy.json
aws iam attach-role-policy --role-name ${CLUSTER_NAME}-alb-controller-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${CLUSTER_NAME}-alb-controller-policy
ALB_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-alb-controller-role --query 'Role.Arn' --output text)

kubectl create serviceaccount aws-load-balancer-controller -n kube-system

aws eks create-pod-identity-association --cluster-name $CLUSTER_NAME \
  --namespace kube-system --service-account aws-load-balancer-controller --role-arn $ALB_ROLE_ARN

kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$AWS_REGION \
  --set vpcId=$VPC_ID

kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
```

Pin the ALB controller's IAM policy/chart to whatever the [current release](https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases) is — `v2.9.2` above is illustrative, verify before running.

## Verify

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller   # 2 replicas Running
kubectl -n kube-system logs deploy/aws-load-balancer-controller | tail -20               # no AccessDenied errors

kubectl create deployment hello --image=nginx
kubectl expose deployment hello --port=80 --type=LoadBalancer \
  --overrides '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-type":"nlb"}}}'
kubectl get svc hello -w    # EXTERNAL-IP populates within ~2 minutes
curl -sf http://$(kubectl get svc hello -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
kubectl delete svc hello deployment hello
```

## Resume variables (new shell)

```bash
ALB_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-alb-controller-role --query 'Role.Arn' --output text)
```

Next: [08-post-install-validation.md](08-post-install-validation.md)
