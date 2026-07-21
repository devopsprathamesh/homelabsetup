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
  playbooks/
    lab-hostnames.yml       # adds lab-<hostname> aliases to /etc/hosts on every node
```

## Inventory groups

| Group          | Hosts                    | Role                        |
|----------------|---------------------------|------------------------------|
| `loadbalancer` | server (192.168.56.10)    | Load balancer / entry point |
| `masters`      | master1, master2, master3  | Control plane (HA trio)     |
| `workers`      | node1, node2, node3        | Worker nodes                |
| `k8s_cluster`  | masters + workers          | Parent group for cluster-wide plays |

All hosts resolve via `/etc/hosts` entries already present on `server`
(added by the Vagrant provisioning); `ansible_host` IPs are set in the
inventory too so it stays usable if copied elsewhere.

## Syncing changes to `server`

After editing anything here, push the whole directory to the control node
(simplest way to keep `~/ansible/` on `server` in sync as this grows):

```bash
scp -r ansible.cfg inventory playbooks admin@lab-server:~/ansible/
```

## Usage (on `server`)

```bash
ssh admin@lab-server
cd ~/ansible

ansible all --list-hosts     # sanity-check the inventory
ansible all -m ping          # verify connectivity to every node
ansible masters -m ping      # target just one group
```

## Playbooks

### `playbooks/lab-hostnames.yml`

Adds a `lab-<hostname>` alias for every node to `/etc/hosts` on **every**
node (`server`, `master1-3`, `node1-3`) — e.g. `192.168.56.11
lab-master1` — alongside the plain-name entries Vagrant already put there.
The `kubernetes-hardway` docs assume these `lab-*` names resolve (e.g.
`ssh admin@lab-master1`); this is what makes that work when you're driving
the guide from `server` itself instead of your desktop.

Managed via a marked block (`ansible_managed`-style begin/end comments),
so it's safe to re-run — it reconciles that one block and never touches
the Vagrant-managed lines above it.

```bash
ssh admin@lab-server
cd ~/ansible

ansible-playbook playbooks/lab-hostnames.yml --diff   # --diff shows what changed
```

Verify:

```bash
ansible all -a "getent hosts lab-master1 lab-node1 lab-server"
```

`vagrant/scripts/provision-common.sh` manages its own separate marked
block (`# lab-nodes-start` / `# lab-nodes-end`) for the plain-name
entries and only ever touches that block — so this playbook's block
survives a normal `vagrant up` *and* an explicit `vagrant provision` on an
existing VM. Only a full `vagrant destroy` + `vagrant up` rebuilds the VM
(and its `/etc/hosts`) from scratch, wiping the ansible-managed block too
— re-run this playbook after that, or after adding a new node to the
inventory.
