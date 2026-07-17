# 12 — Troubleshooting

## `ansible-playbook` hangs or times out on a specific host

Usually SSH, not Ansible. Check directly first:

```bash
ssh admin@lab-node2 'hostname'
```

If that hangs too, the VM itself may be wedged — `vagrant status`, then
`vagrant reload node2` if needed, before re-running the playbook.

## `apt` lock contention during `cluster.yml`

Ubuntu's unattended-upgrades can hold `/var/lib/dpkg/lock-frontend` right
when Kubespray tries to install packages. Symptom: a task fails with
`Could not get lock`. Fix on the affected node, then re-run:

```bash
ssh admin@lab-<node>
sudo systemctl stop unattended-upgrades
sudo killall apt apt-get 2>/dev/null; sleep 5
```

Consider disabling `unattended-upgrades` cluster-wide for lab nodes to stop
this recurring — it's fighting Kubespray's own package management.

## Task fails with a container image pull error

Almost always transient DNS/network flakiness on first pull, or Docker
Hub rate-limiting anonymous pulls. Re-run the same command (idempotent);
if it recurs specifically for Docker Hub images, consider setting
`docker_hub_mirror`/`registry_mirror` vars, or authenticate pulls.

## `etcd` health check task fails / times out

Check etcd's own view of cluster health directly on any master:

```bash
ssh admin@lab-master1
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --cluster \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/member-master1.pem \
  --key=/etc/ssl/etcd/ssl/member-master1-key.pem
```

If a member is unhealthy, check clock skew between masters first (`etcd`
is sensitive to it) — `timedatectl status` on each, then `chrony`/`ntp` if
they've drifted.

## `kubectl` can't reach the API after bootstrap

1. Confirm HAProxy is actually forwarding (doc 05, step 4):
   `curl -sk https://192.168.56.10:6443/version`
2. If that fails but hitting a master directly works
   (`curl -sk https://192.168.56.11:6443/version`), the problem is HAProxy
   config/service, not the cluster — recheck `/etc/haproxy/haproxy.cfg` and
   `sudo systemctl status haproxy`.
3. If direct-to-master also fails, the apiserver itself is the problem —
   `kubectl` here won't help; SSH to the master and check
   `sudo crictl ps | grep apiserver` and its logs.

## A node is `NotReady` after bootstrap

```bash
kubectl describe node node2
```

Common causes for this lab specifically:

- CNI (Calico) pod not yet `Running` on that node — check
  `kubectl get pods -n kube-system -o wide | grep node2`.
- Swap got re-enabled (shouldn't happen, but confirm):
  `ssh admin@lab-node2 swapon --show` should print nothing.

## Playbook succeeds but a change you made to `group_vars` didn't take effect

Confirm which file Kubespray actually merged the value from — `group_vars`
merges every `.yml` file in a directory, so a duplicate key in two files
resolves by (undocumented-feeling) file-load order. Grep for the key across
the whole `group_vars` tree to check for a conflicting duplicate:

```bash
grep -rn "loadbalancer_apiserver" inventory/mycluster/group_vars/
```

Next: [13 — Cleanup & Teardown](13-cleanup-and-teardown.md)
