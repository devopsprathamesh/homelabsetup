# 16 — Cleanup

The true last step — run this once you're actually done exploring, not
right after [12](12-smoke-test.md). The whole point of
[14 — HA Deep Dive](14-ha-deep-dive.md) and the disaster-recovery module
after it is to keep breaking and un-breaking this same cluster; tearing it
down here throws that lab away. Two levels: reset just Kubernetes (keep
the VMs, so you can re-run the guide) or destroy the VMs entirely.

## Option A — Reset Kubernetes, keep the VMs

Useful if you want to re-run this guide from scratch without waiting for
`vagrant up` again.

**Run on:** `master1`, `master2`, `master3` — repeat on each.

```bash
sudo systemctl stop kube-apiserver kube-controller-manager kube-scheduler etcd
sudo systemctl disable kube-apiserver kube-controller-manager kube-scheduler etcd
sudo rm -rf /var/lib/kubernetes /var/lib/etcd /etc/etcd /etc/kubernetes
sudo rm -f /etc/systemd/system/{kube-apiserver,kube-controller-manager,kube-scheduler,etcd}.service
rm -rf ~/k8s-the-hard-way
sudo systemctl daemon-reload
```

**Run on:** `node1`, `node2`, `node3` — repeat on each.

```bash
sudo systemctl stop kubelet kube-proxy containerd
sudo systemctl disable kubelet kube-proxy containerd
sudo rm -rf /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes \
            /etc/cni /opt/cni /var/lib/containerd /etc/containerd
sudo rm -f /etc/systemd/system/{kubelet,kube-proxy,containerd}.service
rm -rf ~/k8s-the-hard-way
sudo systemctl daemon-reload
sudo ip link delete cnio0 2>/dev/null || true
```

**Run on:** `server`.

```bash
sudo systemctl stop haproxy
sudo systemctl disable haproxy
sudo apt remove -y haproxy
```

If you persisted the pod-network routes from
[10](10-pod-network-routes.md) via netplan, remove that file too.

**Run on:** all 7 VMs — `node1`, `node2`, `node3`, `master1`, `master2`,
`master3`, `server` — whichever of them still have it.

```bash
sudo rm -f /etc/netplan/90-pod-routes.yaml
sudo netplan apply
```

Finally, clear the local `~/k8s-the-hard-way` scratch directory (certs,
keys, kubeconfigs generated in this guide) and remove the
`kubernetes-the-hard-way` context from `~/.kube/config` if you're starting
over.

**Run on:** client machine.

```bash
rm -rf ~/k8s-the-hard-way
kubectl config delete-context kubernetes-the-hard-way 2>/dev/null || true
kubectl config delete-cluster kubernetes-the-hard-way 2>/dev/null || true
kubectl config delete-user admin 2>/dev/null || true
```

## Option B — Destroy the VMs entirely

**Run on:** your host machine (not any lab VM — the machine that runs
`vagrant`), inside `vagrant/`.

```bash
cd vagrant
vagrant destroy -f
```

This is destructive and irreversible for anything not committed to this
repo — confirm you don't need any in-VM state before running it. Rebuild
with `vagrant up` per the root [README](../../README.md).
