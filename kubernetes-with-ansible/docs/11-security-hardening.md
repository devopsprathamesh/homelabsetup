# 11 — Security Hardening

Kubespray gets you a *correctly assembled* cluster — HA control plane,
proper certs, a real CNI. "Production-grade" also means the gaps below,
which are either inherited from this lab's Vagrant provisioning or are
Kubespray defaults chosen for broad compatibility rather than max security.
Treat this doc as a checklist, not optional reading.

## 1. The `admin:x` password (inherited from the Vagrant layer)

`vagrant/scripts/provision-common.sh` creates the `admin` user with
password `x` and SSH password auth enabled, explicitly because the VMs sit
on an isolated `192.168.56.0/24` host-only network. If you ever expose any
of these nodes beyond that network (bridged networking, port-forwarding,
cloud deployment), this is the first thing to fix:

```bash
# on each node, or via ansible k8s_cluster -m ...:
sudo passwd admin                          # set a real password, or...
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' \
  /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
sudo systemctl restart ssh
```

## 2. Single LB = SPOF (from doc 05)

Already flagged when built: `server` going down takes the whole cluster's
reachability with it, even though masters themselves are HA. Fix with a
second LB + `keepalived`, or `kube-vip` static pods on the masters — see
doc 05's closing section, and see it triggered hands-on in
[13 — HA Deep Dive](13-ha-deep-dive.md) §7.

## 3. etcd is stacked, not dedicated

Doc 03's choice. For a real production cluster, run etcd on its own 3+
hosts, separate from `kube_control_plane` — protects etcd's latency
sensitivity from apiserver/scheduler load, and lets you scale/patch them
independently.

## 4. Secrets at rest

Check whether encryption-at-rest for Secrets is enabled:

```bash
kubectl -n kube-system exec -it $(kubectl -n kube-system get pod -l component=kube-apiserver -o jsonpath='{.items[0].metadata.name}') \
  -- cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep encryption
```

If not set, Kubespray supports it via `kube_encrypt_secret_data: true` in
`group_vars/k8s_cluster/k8s-cluster.yml` — must be set **before** the
initial `cluster.yml` run for a clean bootstrap (retrofitting onto a live
cluster requires re-encrypting existing Secrets manually).

## 5. RBAC and network policy

Kubespray enables RBAC by default (verify: `kubectl api-versions | grep rbac`)
but ships no restrictive policies out of the box — that's on you:

- Audit default `ClusterRoleBinding`s (`cluster-admin` bound to anything
  broader than intended?).
- Calico is installed with networking, not policy enforcement — write
  actual `NetworkPolicy`/`GlobalNetworkPolicy` resources to restrict
  pod-to-pod traffic; nothing does this for you by default.

## 6. Secrets in your Ansible/Kubespray config itself

If you add any credentials into `group_vars` (registry pull secrets, cloud
provider keys for a CSI driver, etc.), never commit them in plaintext.
Use `ansible-vault`:

```bash
ansible-vault encrypt inventory/mycluster/group_vars/all/secrets.yml
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml --ask-vault-pass
```

## 7. kubeconfig distribution

The admin kubeconfig pulled in doc 08 grants full cluster-admin. Don't copy
it to more places than necessary, and don't commit it to this repo (it's
already excluded by nothing specific — add a `.gitignore` entry if you
generate one inside this directory). For anything beyond solo lab use,
issue scoped `ServiceAccount`/`ClusterRole` credentials per user instead of
sharing the admin config.

## 8. Audit logging

Not enabled by Kubespray defaults. For real production, set
`kubernetes_audit: true` and related `audit_*` vars in
`group_vars/k8s_cluster/k8s-cluster.yml` before bootstrap, and ship the
resulting audit log somewhere durable (this lab has nowhere to ship it —
note that as a gap, don't pretend it's solved).

## 9. Resource headroom (from doc 01)

2 vCPU/2GB masters is kubeadm's floor, not a production number. Real
control planes budget significantly more so the apiserver/etcd don't
compete with kubelet/system daemons under load. If this lab ever needs to
prove it handles real traffic (not just "does it boot"), bump master RAM
in `../vagrant/Vagrantfile` before drawing conclusions from load tests.

Next: [12 — Troubleshooting](12-troubleshooting.md)
