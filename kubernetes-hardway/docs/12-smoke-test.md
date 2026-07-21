# 12 — Smoke Test

Run from your **client machine** unless noted. This exercises every layer
built in this guide: secrets encryption, scheduling across all 3 workers,
cross-node pod networking, kubelet log/exec APIs, and Services.

## 1. Data encryption at rest

```bash
kubectl create secret generic kubernetes-the-hard-way \
  --from-literal="mykey=mydata"
```

**Run on:** any one of `master1`/`master2`/`master3`. Read the raw etcd
value and confirm it's encrypted (`k8s:enc:aescbc:v1:key1` prefix, not
plaintext `mydata`):

```bash
sudo ETCDCTL_API=3 etcdctl get /registry/secrets/default/kubernetes-the-hard-way \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem \
  | hexdump -C | head
```

## 2. Deployments schedule across all workers

```bash
kubectl create deployment nginx --image=nginx --replicas=6
kubectl rollout status deployment/nginx
kubectl get pods -o wide
```

Confirm the `NODE` column shows a spread across `node1`, `node2`, and
`node3` — not all landing on one node (the default scheduler spreads by
resource fit, so with 6 replicas and 3 idle nodes you should see roughly
2 per node).

## 3. Cross-node pod networking

Pick two pod IPs from step 2 that landed on **different** nodes (from the
`kubectl get pods -o wide` output), then, from inside one pod, curl the
other:

```bash
POD_A=$(kubectl get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
POD_B_IP=$(kubectl get pods -l app=nginx -o jsonpath='{.items[1].status.podIP}')
kubectl exec ${POD_A} -- curl -s -o /dev/null -w "%{http_code}\n" http://${POD_B_IP}
```

Expect `200`. A timeout here almost always means a missing route from
[10 — Pod Network Routes](10-pod-network-routes.md).

## 4. Port forwarding

```bash
POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward ${POD_NAME} 8080:80 &
sleep 2
curl -s http://127.0.0.1:8080 | head -5
kill %1
```

## 5. Logs

```bash
kubectl logs ${POD_NAME}
```

## 6. Exec

```bash
kubectl exec -ti ${POD_NAME} -- nginx -v
```

If steps 4-6 hang or 403, re-check the RBAC binding from
[06 — Bootstrapping the Control Plane §7](06-bootstrapping-control-plane.md#7-rbac-allow-kube-apiserver-to-talk-to-kubelets).

## 7. Services (NodePort)

```bash
kubectl expose deployment nginx --port 80 --type NodePort
NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.56.13:${NODE_PORT}
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.56.14:${NODE_PORT}
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.56.15:${NODE_PORT}
```

Expect `200` from all three node IPs regardless of which node actually
hosts a given nginx pod — that's `kube-proxy`'s iptables rules routing
NodePort traffic to the right backend cluster-wide.

## 8. Control-plane HA (optional, destructive-ish but reversible)

With 3 masters, the cluster tolerates losing any one node — both the
apiserver (via the LB) and etcd (via quorum) stay fully functional.

**Run on:** client machine — the `ssh admin@lab-master1` calls below reach
out to `master1` for you; you stay on your own shell throughout.

```bash
ssh admin@lab-master1 'sudo systemctl stop kube-apiserver'
kubectl get nodes   # should still succeed, served by master2/master3 via the LB
ssh admin@lab-master1 'sudo systemctl start kube-apiserver'
```

To specifically confirm etcd quorum survives a single-node loss (not just
the apiserver), stop etcd itself on one master and confirm writes still
work through the other two.

**Run on:** client machine (same as above — `ssh` reaches `master1` for
you).

```bash
ssh admin@lab-master1 'sudo systemctl stop etcd'
kubectl create namespace etcd-ha-test   # a write, not just a read — proves quorum held
kubectl delete namespace etcd-ha-test
ssh admin@lab-master1 'sudo systemctl start etcd'
```

## Cleanup of smoke-test objects

```bash
kubectl delete deployment nginx
kubectl delete svc nginx
kubectl delete secret kubernetes-the-hard-way
```

If everything above passed, the cluster is fully functional end to end.

Next: [14 — High Availability Deep Dive](14-ha-deep-dive.md) to actually
explore *why* it survives what it survives, rather than just confirming
that it does. [16 — Cleanup](16-cleanup.md) is there whenever you're done
experimenting, not a required next step.
