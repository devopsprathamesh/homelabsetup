# 10 — Upgrading the Cluster

## 1. Back up etcd first — always

Every upgrade path below assumes you can roll back. Take a snapshot on each
master before touching anything:

```bash
ssh admin@lab-master1
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup-$(date +%F).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-master1.pem \
  --key=/etc/ssl/etcd/ssl/member-master1-key.pem
```

Copy the snapshot off-box (`scp` to `server` or your desktop) — a backup
that lives only on the host it's backing up doesn't survive that host
dying.

## 2. Two kinds of upgrade

- **Kubernetes version bump within the same Kubespray release** — edit
  `kube_version` in `group_vars/k8s_cluster/k8s-cluster.yml` to another
  version that specific Kubespray release supports, then run
  `upgrade-cluster.yml`.
- **Kubespray version bump** (e.g. v2.31.0 → a later tag) — this also moves
  the default `kube_version` and possibly Calico/containerd versions
  together. Re-clone or `git fetch && git checkout <new-tag>` in
  `~/kubespray`, re-check `group_vars` for any renamed/deprecated keys
  (read that release's changelog), then run `upgrade-cluster.yml`.

Don't skip Kubespray releases blindly — check the release notes between
your current tag and the target for breaking `group_vars` changes.

## 3. Run the upgrade

```bash
cd ~/kubespray
source ~/kubespray-venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini \
  --become --become-user=root \
  upgrade-cluster.yml
```

This upgrades one control-plane node at a time (respecting etcd quorum),
then workers — never all at once. Expect it to take noticeably longer than
the initial `cluster.yml` run for a cluster this size.

## 4. Verify after

```bash
kubectl get nodes -o wide     # check VERSION column on every node
kubectl get pods -n kube-system
```

Re-run the smoke test from
[08 — Verifying the Cluster](08-verifying-the-cluster.md), step 6.

## 5. If it goes wrong

Restore from the etcd snapshot taken in step 1
(Kubespray's `docs/etcd.md` covers the restore procedure) rather than
improvising — a partially-upgraded control plane with a corrupted etcd
state is not something to debug live on a lab you rely on.

Next: [11 — Security Hardening](11-security-hardening.md)
