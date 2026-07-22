# 14 — Disaster Recovery

[13 — HA Deep Dive](13-ha-deep-dive.md) §5 drew the line between
*degraded* (etcd quorum lost, but every member's data directory is still
intact — recoverable by just letting kubelet re-manage the static pod) and
*actually down* (a data directory is gone for good). This doc is what you
do when you're on the wrong side of that line, plus the related-but-distinct
case of rebuilding one lost master while the other two are still fine.

| Scenario | What's lost | Fix |
|---|---|---|
| Quorum lost, data intact (13 §5) | Nothing — just availability | Let kubelet re-manage the static pod |
| Quorum lost, data **gone** (§2 below) | Everything since the last snapshot | Restore all 3 members from a snapshot |
| One master's disk is gone, other 2 fine (§3 below) | Just that member | Rebuild the VM, recover it as an etcd member via Kubespray's own recovery playbook |

Run everything below from `server` unless a step says otherwise, same as
[13](13-ha-deep-dive.md).

## 1. Taking snapshots (do this before you need it)

A snapshot from any single healthy member captures the *whole* cluster's
state — etcd's Raft log means every member already holds the full
replicated data, not just its own shard.

**Run on:** any one master, e.g. `master1`.

```bash
sudo mkdir -p /var/backups/etcd
sudo ETCDCTL_API=3 etcdctl snapshot save \
  /var/backups/etcd/snapshot-$(date +%Y%m%d%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-master1.pem \
  --key=/etc/ssl/etcd/ssl/member-master1-key.pem

sudo ETCDCTL_API=3 etcdctl snapshot status \
  /var/backups/etcd/snapshot-*.db --write-out=table
```

A snapshot sitting only on the machine that might be the next thing to
fail isn't a backup — copy it off-box. `server` is the natural place here
(it's already the hub every other doc SSHes/scps through), though a real
production setup would push it further off-site than a single VM in the
same lab (same honesty-about-limits point [13](13-ha-deep-dive.md) §7 made
about the LB):

```bash
scp admin@lab-master1:/var/backups/etcd/snapshot-*.db ~/etcd-backups/
```

### Automate it — a manual snapshot is only as good as your memory

A systemd timer on `master1` beats a memorized `cron` line, but either
works. Timer version:

```ini
# /etc/systemd/system/etcd-snapshot.service
[Unit]
Description=etcd snapshot

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash -c ' \
  ETCDCTL_API=3 etcdctl snapshot save /var/backups/etcd/snapshot-$(date +%%Y%%m%%d%%H%%M).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-master1.pem \
  --key=/etc/ssl/etcd/ssl/member-master1-key.pem'
```

```ini
# /etc/systemd/system/etcd-snapshot.timer
[Unit]
Description=Hourly etcd snapshot

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now etcd-snapshot.timer
systemctl list-timers etcd-snapshot.timer
```

Pair it with retention (nothing prunes `/var/backups/etcd` for you) and an
off-box copy — a cron line on `server` pulling the latest snapshot on the
same cadence is enough for a lab:

```bash
# on master1 — keep the last 24 hourly snapshots, drop older ones
find /var/backups/etcd -name 'snapshot-*.db' -mtime +1 -delete
```

## 2. Full quorum loss with data loss — restore from a snapshot

This is deliberately destructive — only run the "lose the data" block in a
lab. **Anything written after the snapshot you restore from is gone**;
that's the actual cost here, not a detail to gloss over.

Simulate it (skip on a real incident — the data's already gone by
definition):

```bash
# on master1, master2, master3
sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/etcd.yaml.bak
sudo rm -rf /var/lib/etcd
```

Copy the snapshot to each master first:

```bash
scp ~/etcd-backups/snapshot-XXXXXXXX.db admin@lab-master1:~/
scp ~/etcd-backups/snapshot-XXXXXXXX.db admin@lab-master2:~/
scp ~/etcd-backups/snapshot-XXXXXXXX.db admin@lab-master3:~/
```

**Restore on each master — same snapshot file on all three, but each with
its own `--name` and `--initial-advertise-peer-urls`:**

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

`--initial-cluster-token` must be **different from the original** — a
restore forms a brand-new Raft cluster identity that happens to start
pre-loaded with the snapshot's key-value data; it isn't resuming the old
cluster's term. Fix ownership/permissions the restore expects, then bring
the static pod back:

```bash
# on master1, master2, master3 — roughly together
sudo chown -R root:root /var/lib/etcd
sudo chmod 700 /var/lib/etcd
sudo mv /tmp/etcd.yaml.bak /etc/kubernetes/manifests/etcd.yaml
```

Verify:

```bash
ssh admin@lab-master1 'sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-master1.pem \
  --key=/etc/ssl/etcd/ssl/member-master1-key.pem'
```

Expect all three `started`. `kube-apiserver` reconnects to its local etcd
on its own once the static pod is healthy again, but forcing a clean
restart on each master removes any doubt:

```bash
ssh admin@lab-master1 'sudo crictl ps | grep apiserver'   # note the container ID
ssh admin@lab-master1 'sudo crictl stop <that-container-id>'   # kubelet recreates it immediately
```

```bash
kubectl get nodes
kubectl get deployments -A
```

Anything created after the snapshot is simply gone from these lists —
expected, not a sign something went wrong. Kubelets on `node1-3` reconnect
and re-report on their own; nothing needs to change there.

## 3. Rebuilding one lost master, keeping quorum on the other two

Different problem from §2: here `master2` and `master3`'s etcd are fine,
only `master1`'s VM/disk is gone. Quorum was never lost (2 of 3 is still a
majority), so this is a targeted repair, not a cluster-wide restore.

**Step 1 — remove the dead member, from a surviving master:**

```bash
ssh admin@lab-master2 'sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-master2.pem \
  --key=/etc/ssl/etcd/ssl/member-master2-key.pem'
```

Find `master1`'s member ID in the output, then remove it — a dead member
still counts against Raft's view of cluster size, so leaving it in place
makes the *effective* quorum tolerance worse, not neutral:

```bash
ssh admin@lab-master2 'sudo ETCDCTL_API=3 etcdctl member remove <master1-member-id> \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-master2.pem \
  --key=/etc/ssl/etcd/ssl/member-master2-key.pem'
```

**Step 2 — rebuild the VM:**

```bash
cd ../vagrant
vagrant destroy master1 -f
vagrant up master1
```

Vagrant's own provisioning re-establishes `admin`'s passwordless SSH/sudo
and `/etc/hosts` on every node automatically. Confirm Ansible reaches it
before touching Kubespray:

```bash
cd ~/ansible && ansible master1 -m ping
```

**Step 3 — recover it as an etcd/control-plane member via Kubespray's
dedicated recovery playbook**, rather than re-running `cluster.yml` or
`scale.yml` — those assume either a fully-fresh cluster or a genuinely new
node, not a name that already exists in the inventory but whose disk was
wiped. Kubespray ships `recover-control-plane.yml` for exactly this case:

```bash
cd ~/kubespray
source ~/kubespray-venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini \
  --become --become-user=root \
  --limit=etcd,kube_control_plane \
  -e kube_control_plane_recovery=true \
  -e etcd_recovery=true \
  recover-control-plane.yml
```

Check that release's `docs/recover_control_plane.md` for the exact
variable names before running this — they've shifted across Kubespray
versions, and this is not a playbook to guess your way through. The
`--limit` deliberately includes `master2`/`master3` too: Kubespray needs a
healthy control-plane host in the play to source the CA and join `master1`
back in, not just the recovering host itself.

**Step 4 — verify:**

```bash
ssh admin@lab-master2 'sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-master2.pem \
  --key=/etc/ssl/etcd/ssl/member-master2-key.pem'
kubectl get nodes -o wide
kubectl get componentstatuses
```

HAProxy ([05](05-load-balancer-haproxy.md)) picks `master1` back up on its
own once its apiserver health check starts passing again — it was never
removed from `haproxy.cfg`'s backend, so no LB config change is needed.

Next: this is the last conceptual module — whenever you're actually done
with the lab, [15 — Cleanup & Teardown](15-cleanup-and-teardown.md) covers
tearing it down.
