# 15 — Disaster Recovery

[14 — HA Deep Dive](14-ha-deep-dive.md) §5 drew the line between
*degraded* (etcd quorum lost, but `/var/lib/etcd` on every member is still
intact — recoverable with nothing but `systemctl start`) and *actually
down* (a data directory is gone for good — disk failure, `rm -rf` gone
wrong, all 3 members lost at once). This doc is what you do when you're
on the wrong side of that line, plus the related-but-distinct case of
rebuilding a single master from nothing.

Two scenarios, and they need different procedures:

| Scenario | What's lost | Fix |
|---|---|---|
| Quorum lost, data intact (14 §5) | Nothing — just availability | `systemctl start etcd` on the stopped members |
| Quorum lost, data **gone** (this doc, §2) | Everything since the last snapshot | Restore all 3 members from a snapshot |
| One master's disk is gone, other 2 fine (this doc, §3) | Just that member | Rebuild the VM, rejoin etcd as a **new** member, redeploy its control plane |

Run everything below from your **client machine** unless a step says
otherwise, same as [14](14-ha-deep-dive.md).

## 1. Taking snapshots (do this before you need it)

A snapshot from any single healthy member captures the whole cluster's
state — etcd's Raft log means every member already has the full replicated
data, not just its own shard.

**Run on:** any one master (e.g. `master1`).

```bash
sudo mkdir -p /var/backups/etcd
sudo ETCDCTL_API=3 etcdctl snapshot save \
  /var/backups/etcd/snapshot-$(date +%Y%m%d%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem

sudo ETCDCTL_API=3 etcdctl snapshot status \
  /var/backups/etcd/snapshot-*.db --write-out=table
```

A snapshot sitting only on the machine that might be the next thing to
fail isn't a backup — copy it off-box. `server` is the natural place
here (it's already the hub every other doc SSHes/scps through), though a
real production setup would push it further off-site than a single VM in
the same lab (same honesty-about-limits point [14](14-ha-deep-dive.md) §7
made about the LB):

```bash
scp admin@lab-master1:/var/backups/etcd/snapshot-*.db ~/etcd-backups/
```

Automate this on a schedule (cron, systemd timer) in anything beyond a
lab — a manual snapshot is only as good as your memory to run it before
the disaster, not after.

## 2. Full quorum loss with data loss — restore from a snapshot

This is deliberately destructive to simulate — only run the "lose the
data" part in a lab. **Anything written after the snapshot you restore
from is gone**; that's the actual cost of this scenario, not a detail to
gloss over.

Simulate it (skip this block on a real incident — the data's already
gone by definition):

```bash
# on master1, master2, master3
sudo systemctl stop etcd
sudo rm -rf /var/lib/etcd
```

**Restore, on `master1`, `master2`, and `master3` — same snapshot file on
all three, but each with its own `--name` and `--initial-advertise-peer-urls`:**

```bash
# copy the snapshot to each master first
scp ~/etcd-backups/snapshot-XXXXXXXX.db admin@lab-master1:~/
scp ~/etcd-backups/snapshot-XXXXXXXX.db admin@lab-master2:~/
scp ~/etcd-backups/snapshot-XXXXXXXX.db admin@lab-master3:~/
```

```bash
# On master1:
sudo ETCDCTL_API=3 etcdctl snapshot restore ~/snapshot-XXXXXXXX.db \
  --name master1 \
  --initial-cluster master1=https://192.168.56.11:2380,master2=https://192.168.56.12:2380,master3=https://192.168.56.16:2380 \
  --initial-cluster-token etcd-cluster-1 \
  --initial-advertise-peer-urls https://192.168.56.11:2380 \
  --data-dir /var/lib/etcd

# On master2:
sudo ETCDCTL_API=3 etcdctl snapshot restore ~/snapshot-XXXXXXXX.db \
  --name master2 \
  --initial-cluster master1=https://192.168.56.11:2380,master2=https://192.168.56.12:2380,master3=https://192.168.56.16:2380 \
  --initial-cluster-token etcd-cluster-1 \
  --initial-advertise-peer-urls https://192.168.56.12:2380 \
  --data-dir /var/lib/etcd

# On master3:
sudo ETCDCTL_API=3 etcdctl snapshot restore ~/snapshot-XXXXXXXX.db \
  --name master3 \
  --initial-cluster master1=https://192.168.56.11:2380,master2=https://192.168.56.12:2380,master3=https://192.168.56.16:2380 \
  --initial-cluster-token etcd-cluster-1 \
  --initial-advertise-peer-urls https://192.168.56.16:2380 \
  --data-dir /var/lib/etcd
```

`--initial-cluster-token` must be **different from the original**
(`etcd-cluster-0` from [05](05-bootstrapping-etcd.md)) — a restore forms
a brand-new Raft cluster identity that happens to start pre-loaded with
the snapshot's key-value data; it isn't resuming the old cluster's term.
`etcd.service` itself (`/etc/systemd/system/etcd.service` from
[05](05-bootstrapping-etcd.md) §3) doesn't need edits — it already has
`--initial-cluster-state new` and the same `--data-dir=/var/lib/etcd`,
both correct for a restore too; only the *token* needs to be new, and
that only exists at restore time, not baked into the unit file.

```bash
# on master1, master2, master3 — roughly together, same as the original bootstrap
sudo chmod 700 /var/lib/etcd
sudo chown -R $(whoami):$(whoami) /var/lib/etcd
sudo systemctl start etcd
```

Verify:

```bash
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem
```

Expect all three `started`. `kube-apiserver` on each master reconnects to
its local etcd on its own (no restart needed), but restarting it anyway
guarantees a clean reconnect rather than relying on it noticing:

```bash
sudo systemctl restart kube-apiserver
```

```bash
kubectl get nodes
kubectl get deployments -A
```

Anything created after the snapshot is simply gone from these lists —
that's expected, not a sign something went wrong. Kubelets on `node1-3`
reconnect and re-report on their own; nothing needs to change there.

## 3. Rebuilding one lost master, keeping quorum on the other two

Different problem from §2: here `master2` and `master3`'s etcd are fine,
only `master1`'s VM/disk is gone. This reuses the exact same mechanism as
[05](05-bootstrapping-etcd.md) §6 ("Adding master3 to an already-running
cluster") — from etcd's point of view, a rebuilt `master1` **is** a new
member, not a resumed one; its old member ID died with its data
directory and can't be reused.

**Step 1 — remove the dead member, from a surviving master:**

```bash
ssh admin@lab-master2 'sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem'
```

Find `master1`'s member ID in the output, then:

```bash
ssh admin@lab-master2 'sudo ETCDCTL_API=3 etcdctl member remove <master1-member-id> \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem'
```

**Step 2 — rebuild the VM** (`vagrant destroy master1 && vagrant up
master1` from `vagrant/`, or however you'd recreate it), then bring it up
to the same point every other master started from:

- [01](01-prerequisites.md) — confirm connectivity, swap off, sysctls set
- [02](02-certificate-authority.md) §7 — re-distribute `ca.pem`,
  `ca-key.pem`, `kubernetes.pem`/`kubernetes-key.pem`,
  `service-account.pem`/`service-account-key.pem` to it (same certs as
  before — no need to regenerate, `master1`'s IP is already in their SANs)
- [03](03-kubernetes-configuration-files.md) §6 /
  [04](04-data-encryption-config.md) — re-distribute its kubeconfigs and
  `encryption-config.yaml`

**Step 3 — join etcd as a new member**, mirroring
[05](05-bootstrapping-etcd.md) §6 exactly:

```bash
ssh admin@lab-master2 'sudo ETCDCTL_API=3 etcdctl member add master1 \
  --peer-urls=https://192.168.56.11:2380 \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem'
```

On `master1`: install etcd ([05](05-bootstrapping-etcd.md) §1), copy
certs ([05](05-bootstrapping-etcd.md) §2), create the systemd unit exactly
as in [05](05-bootstrapping-etcd.md) §3 but with
`--initial-cluster-state existing` instead of `new` — same as the
`master3`-addition path this all mirrors:

```bash
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
sudo systemctl status etcd --no-pager
```

**Step 4 — redeploy the control plane on `master1`**, following
[06](06-bootstrapping-control-plane.md) in full (`kube-apiserver`,
`kube-controller-manager`, `kube-scheduler`) — nothing different from a
fresh master, since etcd rejoining is the only piece that needed a
non-standard flag.

Verify the same way [05](05-bootstrapping-etcd.md) §5 and
[06](06-bootstrapping-control-plane.md) §6 did originally:

```bash
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem
kubectl get componentstatuses --kubeconfig ~/k8s-the-hard-way/kubeconfig/admin.kubeconfig
```

HAProxy ([07](07-load-balancer.md)) picks `master1` back up automatically
once its `kube-apiserver` health check starts passing again — no LB
config changes needed, it was never removed from `haproxy.cfg`.

Next: this is the last planned module — [16 — Cleanup](16-cleanup.md)
whenever you're actually done, not a required next step.
