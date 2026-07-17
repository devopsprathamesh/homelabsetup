# 13 — Cleanup

Two levels: reset just Kubernetes (keep the VMs) or destroy the VMs
entirely.

## Option A — Reset Kubernetes, keep the VMs

Useful if you want to re-run this guide from scratch without waiting for
`vagrant up` again.

On **master1** and **master2**:

```bash
sudo systemctl stop kube-apiserver kube-controller-manager kube-scheduler etcd
sudo systemctl disable kube-apiserver kube-controller-manager kube-scheduler etcd
sudo rm -rf /var/lib/kubernetes /var/lib/etcd /etc/etcd /etc/kubernetes
sudo rm -f /etc/systemd/system/{kube-apiserver,kube-controller-manager,kube-scheduler,etcd}.service
sudo rm -f ~/*.pem ~/*.kubeconfig ~/encryption-config.yaml
sudo systemctl daemon-reload
```

On **node1**, **node2**, **node3**:

```bash
sudo systemctl stop kubelet kube-proxy containerd
sudo systemctl disable kubelet kube-proxy containerd
sudo rm -rf /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes \
            /etc/cni /opt/cni /var/lib/containerd /etc/containerd
sudo rm -f /etc/systemd/system/{kubelet,kube-proxy,containerd}.service
sudo rm -f ~/*.pem ~/*.kubeconfig
sudo systemctl daemon-reload
sudo ip link delete cnio0 2>/dev/null || true
```

On **server**:

```bash
sudo systemctl stop haproxy
sudo systemctl disable haproxy
sudo apt remove -y haproxy
```

Remove the pod-network routes from [10](10-pod-network-routes.md) if you
persisted them via netplan (`/etc/netplan/90-pod-routes.yaml` on each
node), and clear your local `~/k8s-the-hard-way` client directory and
`~/.kube/config` context if starting over.

## Option B — Destroy the VMs entirely

From the host, in `vagrant/`:

```bash
cd vagrant
vagrant destroy -f
```

This is destructive and irreversible for anything not committed to this
repo — confirm you don't need any in-VM state before running it. Rebuild
with `vagrant up` per the root [README](../../README.md).
