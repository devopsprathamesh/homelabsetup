# 16 — Cleanup

The true last step — run this once you're actually done exploring, not
right after [12](12-smoke-test.md). The whole point of
[14 — HA Deep Dive](14-ha-deep-dive.md) and
[15 — Disaster Recovery](15-disaster-recovery.md) after it is to keep
breaking and un-breaking this same cluster; tearing it down here throws
that lab away. Two levels: reset just Kubernetes (keep the VMs, so you
can re-run the guide) or destroy the VMs entirely.

## Option A — Reset Kubernetes, keep the VMs

Useful if you want to re-run this guide from scratch without waiting for
`vagrant up` again.

If you followed [13 — Migrating to Cilium](13-migrating-to-cilium.md),
uninstall it first, from the **client machine**, before tearing down the
control plane below (Cilium's own cleanup needs a live API server):

```bash
helm uninstall cilium -n kube-system
```

Its `cilium_host`/`cilium_net`/`cilium_vxlan` interfaces on each node are
harmless to leave — they disappear on next reboot, or `sudo ip link
delete cilium_vxlan cilium_host 2>/dev/null || true` clears them sooner.

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

### Verify the reset actually completed

Spot-check one master and one worker — every command should come back
empty/inactive:

```bash
ssh admin@lab-master1 'systemctl is-active etcd kube-apiserver 2>/dev/null; ls /var/lib/etcd /etc/etcd 2>&1'
# expect: "inactive" (or "not-found") twice, then "No such file or directory" for both dirs

ssh admin@lab-node1 'systemctl is-active kubelet containerd 2>/dev/null; ls /etc/cni /var/lib/kubelet 2>&1; ip link show cnio0 2>&1'
# expect: inactive/not-found, missing dirs, and "does not exist" for cnio0

ssh admin@lab-server 'systemctl is-active haproxy 2>&1; ss -tlnp | grep 6443 || echo "6443 free"'
# expect: inactive/not-found and "6443 free"
```

If any service still reports `active` or a directory survives, re-run that
node's block above — the VMs are then clean enough to restart the guide
from [01](01-prerequisites.md).

## Option B — Destroy the VMs entirely

**Run on:** your host machine (not any lab VM — the machine that runs
`vagrant`), inside `vagrant/`.

```bash
cd 1.vagrant
vagrant destroy -f
```

This is destructive and irreversible for anything not committed to this
repo — confirm you don't need any in-VM state before running it. Rebuild
with `vagrant up` per the root [README](../../README.md).
