# 08. Post-Install Validation Checklist

Run all of this after completing docs 01-07. Replace the autoscaler block with whichever option ([06](06-node-autoscaling.md)) you actually installed.

```bash
# --- Cluster & nodes ---
kubectl get nodes -o wide                          # [ ] 2+ nodes, STATUS=Ready
kubectl cluster-info                                # [ ] control plane + CoreDNS URLs resolve

# --- Core add-ons ---
aws eks list-addons --cluster-name $CLUSTER_NAME --output table            # [ ] eks-pod-identity-agent, vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver all listed
for A in eks-pod-identity-agent vpc-cni kube-proxy coredns aws-ebs-csi-driver; do
  echo -n "$A: "; aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name $A --query 'addon.status' --output text
done                                                 # [ ] every line prints ACTIVE
kubectl get pods -n kube-system                     # [ ] aws-node, kube-proxy, coredns x2, ebs-csi-controller x2, ebs-csi-node, eks-pod-identity-agent all Running

# --- Pod Identity wiring ---
aws eks list-pod-identity-associations --cluster-name $CLUSTER_NAME --output table
# [ ] associations exist for: aws-node, ebs-csi-controller-sa, aws-load-balancer-controller,
#     plus cluster-autoscaler OR karpenter depending which you installed

# --- metrics-server ---
kubectl top nodes                                   # [ ] returns CPU/memory, not an error
kubectl top pods -A

# --- EBS CSI: dynamic PVC provisioning actually works ---
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-test-claim
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: gp2
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc ebs-test-claim -w                   # [ ] STATUS becomes Bound within ~30s
kubectl delete pvc ebs-test-claim

# --- Node autoscaling (pick the block matching what you installed in 06) ---

# If Cluster Autoscaler:
kubectl -n cluster-autoscaler get pods                                    # [ ] Running
kubectl -n cluster-autoscaler logs deploy/cluster-autoscaler | tail -20   # [ ] no AWS auth errors

# If Karpenter:
kubectl -n kube-system get pods -l app.kubernetes.io/name=karpenter       # [ ] Running
kubectl -n kube-system logs deploy/karpenter | tail -20                   # [ ] no AWS auth errors
kubectl get nodepool,ec2nodeclass                                          # [ ] "default" of each, no errors in STATUS

# --- AWS Load Balancer Controller ---
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller   # [ ] 2 replicas Running
kubectl -n kube-system logs deploy/aws-load-balancer-controller | tail -20               # [ ] no AccessDenied errors

# --- End-to-end: a real Service of type LoadBalancer actually provisions an NLB ---
kubectl create deployment hello --image=nginx
kubectl expose deployment hello --port=80 --type=LoadBalancer \
  --overrides '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-type":"nlb"}}}'
kubectl get svc hello -w                             # [ ] EXTERNAL-IP populates within ~2 minutes
curl -sf http://$(kubectl get svc hello -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')   # [ ] returns nginx welcome page
kubectl delete svc hello deployment hello            # clean up the smoke test
```

If anything above doesn't check out, see [09-troubleshooting.md](09-troubleshooting.md).

Done validating? [10-teardown.md](10-teardown.md) has the full reverse-order cleanup when you're finished with this cluster.
