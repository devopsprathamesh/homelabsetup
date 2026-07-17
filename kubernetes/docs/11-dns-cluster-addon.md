# 11 — Deploying the DNS Cluster Add-on (CoreDNS)

Run from your **client machine**, using the remote kubeconfig configured in
[09](09-configuring-kubectl.md).

```bash
kubectl apply -f https://raw.githubusercontent.com/kelseyhightower/kubernetes-the-hard-way/master/deployments/coredns.yaml
```

This manifest deploys CoreDNS with a ClusterIP Service pinned to
`10.32.0.10` — matching the `clusterDNS` value set in every kubelet's
config in [08](08-bootstrapping-worker-nodes.md), and inside
`SERVICE_CIDR` (`10.32.0.0/24`) from the apiserver flags in
[06](06-bootstrapping-control-plane.md). If you changed either of those
values, don't use this manifest as-is — pull it locally and edit the
Service's `clusterIP` and Corefile to match.

## Verify

```bash
kubectl get pods -l k8s-app=kube-dns -n kube-system
kubectl get svc -n kube-system kube-dns
```

Expect the CoreDNS pod(s) `Running` and the Service showing
`ClusterIP 10.32.0.10`.

Functional DNS test:

```bash
kubectl run busybox --image=busybox:1.36 --restart=Never --command -- sleep 3600
kubectl wait --for=condition=Ready pod/busybox --timeout=60s
kubectl exec busybox -- nslookup kubernetes.default
kubectl delete pod busybox
```

Expect `nslookup` to resolve `kubernetes.default` to `10.32.0.1` (the
Kubernetes Service's ClusterIP, always the first address in
`SERVICE_CIDR`).

Next: [12 — Smoke Test](12-smoke-test.md)
