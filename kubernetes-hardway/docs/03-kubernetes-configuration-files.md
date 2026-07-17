# 03 — Kubernetes Configuration Files (kubeconfigs)

Run all of this on the **client machine**, inside `~/k8s-the-hard-way`.

Each kubeconfig bundles a server URL, the CA cert, and a client
cert/key — this is what lets `kubectl`, `kubelet`, `kube-proxy`, etc. auth
to the API server. Worker-facing kubeconfigs point at the **load balancer**
(`192.168.56.10:6443`), not at either master directly, so they keep working
if one control-plane node goes down.

```bash
LB_IP=192.168.56.10
```

## 1. kubelet kubeconfigs (one per worker node)

```bash
for i in 1 2 3; do
  node="node${i}"

  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${LB_IP}:6443 \
    --kubeconfig=${node}.kubeconfig

  kubectl config set-credentials system:node:${node} \
    --client-certificate=${node}.pem \
    --client-key=${node}-key.pem \
    --embed-certs=true \
    --kubeconfig=${node}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${node} \
    --kubeconfig=${node}.kubeconfig

  kubectl config use-context default --kubeconfig=${node}.kubeconfig
done
```

## 2. kube-proxy kubeconfig

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${LB_IP}:6443 \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
```

## 3. kube-controller-manager kubeconfig

Talks to the **local** API server over loopback (each master runs its own
controller-manager against its own apiserver instance), so this one points
at `127.0.0.1:6443`, not the LB.

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=kube-controller-manager.pem \
  --client-key=kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
```

## 4. kube-scheduler kubeconfig

Also loopback, same reasoning.

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=kube-scheduler.pem \
  --client-key=kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
```

## 5. admin kubeconfig

Also loopback — used for local `kubectl` diagnostics on a master itself.
The separate remote admin kubeconfig (pointed at the LB, for your desktop)
is built in [09 — Configuring kubectl](09-configuring-kubectl.md).

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=admin.kubeconfig

kubectl config use-context default --kubeconfig=admin.kubeconfig
```

## 6. Distribute kubeconfigs

```bash
for node in node1 node2 node3; do
  scp ${node}.kubeconfig kube-proxy.kubeconfig admin@lab-${node}:~/
done

for master in master1 master2 master3; do
  scp admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig \
      admin@lab-${master}:~/
done
```

Next: [04 — Data Encryption Config](04-data-encryption-config.md)
