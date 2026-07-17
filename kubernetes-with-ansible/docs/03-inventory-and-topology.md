# 03 — Inventory & Topology

All of this runs on `server`, inside `~/kubespray`, with the venv activated.

## 1. Copy the sample inventory

Never edit `inventory/sample` in place — copy it per-cluster so upgrades to
Kubespray itself don't clobber your config:

```bash
cp -rfp inventory/sample inventory/mycluster
```

## 2. Write the inventory

Kubespray's group names are fixed by its playbooks — they're *not* the same
names as `../ansible/inventory/hosts.ini` (`masters`/`workers`) used
elsewhere in this repo:

| Kubespray group     | Maps to (this lab)          | Role |
|----------------------|------------------------------|------|
| `etcd`               | master1, master2, master3   | etcd cluster (stacked on control plane) |
| `kube_control_plane` | master1, master2, master3   | apiserver / controller-manager / scheduler |
| `kube_node`          | node1, node2, node3          | kubelet / kube-proxy, runs workloads |
| `k8s_cluster`        | (children: the two above)   | parent group most playbooks target |

`server` is deliberately **not** in any of these groups — it's the LB and
Ansible control node, not a cluster member.

Create `inventory/mycluster/inventory.ini`:

```ini
[kube_control_plane]
master1 ansible_host=192.168.56.11
master2 ansible_host=192.168.56.12
master3 ansible_host=192.168.56.16

[etcd]
master1 ansible_host=192.168.56.11
master2 ansible_host=192.168.56.12
master3 ansible_host=192.168.56.16

[kube_node]
node1 ansible_host=192.168.56.13
node2 ansible_host=192.168.56.14
node3 ansible_host=192.168.56.15

[k8s_cluster:children]
kube_control_plane
kube_node

[all:vars]
ansible_user=admin
ansible_become=true
ansible_become_method=sudo
```

Notes on the choices here:

- **etcd stacked on the control plane nodes** (not a separate `etcd` group
  of dedicated hosts) — the production-preferred pattern is a *dedicated*
  etcd group on its own hosts, since etcd is latency-sensitive and control
  plane load can starve it. With only 7 VMs total and 2GB RAM masters,
  dedicating 3 more VMs to etcd alone isn't practical for this lab; stacked
  etcd is Kubespray's default and is what `kubernetes-hardway` also does in
  this repo. Flagged again in
  [11 — Security Hardening](11-security-hardening.md).
- **Odd control-plane count (3)** — etcd Raft needs a majority; 3 members
  tolerate losing any 1 while staying writable. Keep this odd if you scale
  up (5, not 4).
- `ansible_become=true` — every Kubespray task needs root; `admin` already
  has passwordless sudo from the Vagrant provisioning.

## 3. Verify the inventory parses and matches expectations

```bash
ansible-inventory -i inventory/mycluster/inventory.ini --list | python3 -m json.tool | head -40
ansible -i inventory/mycluster/inventory.ini all -m ping
```

All 6 hosts (masters + nodes — not `server`) should respond `pong`, using
this *new* inventory file, not `~/ansible/inventory/hosts.ini`.

Next: [04 — Cluster Configuration](04-cluster-configuration.md)
