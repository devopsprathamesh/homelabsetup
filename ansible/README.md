# Ansible inventory

Inventory for the 6-node lab cluster (see the [top-level README](../README.md)
for how the nodes themselves are provisioned via Vagrant).

**Ansible itself is only installed on `server`** (192.168.56.10), not on this
desktop — `server` is the control node. The files here are kept in git for
version control and mirrored to `~/ansible/` on `server`, where they're
actually used.

## Layout

```
ansible/
  ansible.cfg              # remote_user=admin, points at inventory/hosts.ini
  inventory/
    hosts.ini               # groups: loadbalancer, masters, workers, k8s_cluster
```

## Inventory groups

| Group          | Hosts                    | Role                        |
|----------------|---------------------------|------------------------------|
| `loadbalancer` | server (192.168.56.10)    | Load balancer / entry point |
| `masters`      | master1, master2           | Control plane (HA pair)     |
| `workers`      | node1, node2, node3        | Worker nodes                |
| `k8s_cluster`  | masters + workers          | Parent group for cluster-wide plays |

All hosts resolve via `/etc/hosts` entries already present on `server`
(added by the Vagrant provisioning); `ansible_host` IPs are set in the
inventory too so it stays usable if copied elsewhere.

## Syncing changes to `server`

After editing `inventory/hosts.ini` or `ansible.cfg` here, push them to the
control node:

```bash
scp ansible.cfg admin@lab-server:~/ansible/ansible.cfg
scp inventory/hosts.ini admin@lab-server:~/ansible/inventory/hosts.ini
```

## Usage (on `server`)

```bash
ssh admin@lab-server
cd ~/ansible

ansible all --list-hosts     # sanity-check the inventory
ansible all -m ping          # verify connectivity to every node
ansible masters -m ping      # target just one group
```

No playbooks yet — this is inventory/connectivity only, ready to build on.
