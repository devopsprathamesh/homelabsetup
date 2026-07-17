# 06 — Preflight Checks

All of this runs on `server`, inside `~/kubespray`, with the venv activated.
None of these steps change anything on the target nodes — run them all
before touching `cluster.yml`.

## 1. Syntax-check the playbook against your inventory

```bash
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml --syntax-check
```

Catches YAML/inventory mistakes without touching any host.

## 2. List the hosts and tasks that would run, without running them

```bash
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml --list-hosts
```

Confirm it's exactly `master1, master2, master3, node1, node2, node3` —
if `server` shows up here, the inventory groups from doc 03 are wrong.

## 3. Gather real facts from every target host

This is Kubespray's own read-only facts pass — a good proxy for "will
Ansible actually be able to talk to and inspect every node the real run
needs":

```bash
ansible-playbook -i inventory/mycluster/inventory.ini facts.yml
```

Should finish with `failed=0` across all 6 hosts.

## 4. Re-confirm resource and prerequisite state

Same checks as doc 01, but now through the Kubespray inventory specifically
(catches any drift since then):

```bash
ansible -i inventory/mycluster/inventory.ini k8s_cluster -m shell -a \
  "swapon --show; free -h | grep Mem; nproc"
```

## 5. Know the limits of `--check` mode here

Kubespray's playbooks are **not** fully idempotent under Ansible's
`--check` (dry-run) mode — many tasks that shell out to `kubeadm`,
`systemctl`, or download binaries don't support check mode and will be
skipped rather than meaningfully validated. Don't treat a clean `--check`
run as proof the real run will succeed; treat steps 1–4 above as the real
preflight, and rely on `cluster.yml` itself being safe to re-run (Doc 07)
if something fails partway.

## 6. Confirm the HAProxy LB is live before proceeding

```bash
sudo ss -tlnp | grep 6443
```

If doc 05 hasn't been done yet, do it now — `cluster.yml` will bake the LB
address into certs on first run.

Next: [07 — Running the Playbook](07-running-the-playbook.md)
