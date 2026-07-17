# 09 — Configuring kubectl for Remote Access

Run on your **client machine** (desktop), inside `~/k8s-the-hard-way`.

This builds a kubeconfig that talks to the cluster through the load
balancer, using the admin client cert generated in
[02](02-certificate-authority.md) — this is the config you'll actually use
day-to-day, distinct from the loopback `admin.kubeconfig` copies living on
each master (used only for local diagnostics on that node).

```bash
LB_IP=192.168.56.10

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${LB_IP}:6443

kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem

kubectl config set-context kubernetes-the-hard-way \
  --cluster=kubernetes-the-hard-way \
  --user=admin

kubectl config use-context kubernetes-the-hard-way
```

This writes into `~/.kube/config` on the client machine (kubectl's default
location) rather than a standalone file, so it becomes your normal
`kubectl` context immediately.

## Verify

```bash
kubectl version
kubectl get componentstatuses
kubectl get nodes
```

Expect all 3 worker nodes `Ready`, and API version info returned without
TLS errors. If you get a certificate error mentioning an IP not in the
SAN list, double check [02](02-certificate-authority.md) step 5 included
`192.168.56.10` in `-hostname=` for the `kubernetes` cert.

Next: [10 — Pod Network Routes](10-pod-network-routes.md)
