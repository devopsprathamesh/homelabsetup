# 09 — Scaling Nodes

All of this runs on `server`, inside `~/kubespray`, with the venv activated.

## Adding a worker node

1. Provision the VM first (outside Kubespray) — extend the `NODES` array in
   `../vagrant/Vagrantfile` and `vagrant up <name>`, following the "Add/remove
   nodes" section of the root README. Re-run `vagrant provision` on existing
   nodes so `/etc/hosts` picks up the new one.

2. Add it to `inventory/mycluster/inventory.ini`, in `kube_node` and the
   `k8s_cluster:children` group already covers it:

   ```ini
   [kube_node]
   node1 ansible_host=192.168.56.13
   node2 ansible_host=192.168.56.14
   node3 ansible_host=192.168.56.15
   node4 ansible_host=192.168.56.17
   ```

3. Run `scale.yml`, **not** `cluster.yml` — it's written to safely add nodes
   without re-touching the existing control plane's certs/etcd state:

   ```bash
   ansible-playbook -i inventory/mycluster/inventory.ini \
     --become --become-user=root \
     scale.yml
   ```

4. Verify:

   ```bash
   kubectl get nodes
   ```

## Adding a control-plane node

Same shape, but:

- Add the new host to **both** `kube_control_plane` and `etcd` in the
  inventory (keep the stacked-etcd pattern from doc 03).
- Keep the total control-plane count **odd** (going 3→5, not 3→4) — an even
  etcd member count adds a host without adding fault tolerance.
- Also add it as a `server` in `05-load-balancer-haproxy.md`'s HAProxy
  backend, and re-run the HAProxy config step — otherwise the LB never
  routes to it.
- Run `scale.yml` the same way as above.

## Removing a node

Use Kubespray's dedicated removal playbook — don't just delete inventory
lines and hope, since that skips draining and etcd member removal:

```bash
ansible-playbook -i inventory/mycluster/inventory.ini \
  --become --become-user=root \
  remove-node.yml \
  -e node=node3
```

This cordons and drains `node3`, removes it from the cluster, then you can
delete its inventory line and (if desired) `vagrant destroy node3`.

For removing a **control-plane** member, confirm the remaining etcd member
count stays a majority-safe number (don't go 3→2 and call it done — 2-member
etcd has *worse* fault tolerance than 1, since losing either loses quorum).

Next: [10 — Upgrading the Cluster](10-upgrading-the-cluster.md)
