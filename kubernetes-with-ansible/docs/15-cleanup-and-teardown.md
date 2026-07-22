# 15 — Cleanup & Teardown

Two levels of "tear down," depending on what you want to keep.

If there's any chance you'll want this cluster's state back — even just to
compare against a future attempt — take an etcd snapshot first (see
[14 — Disaster Recovery](14-disaster-recovery.md) §1) and copy it off the
lab network. Both options below are one-way once you actually run them.

## Option A — Reset Kubernetes, keep the VMs

Use Kubespray's own reset playbook — it undoes what `cluster.yml` did
(stops services, removes containers/CNI config/certs/etcd data) without
touching the underlying VM:

```bash
cd ~/kubespray
source ~/kubespray-venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini \
  --become --become-user=root \
  reset.yml
```

It'll prompt for confirmation per host (`-e reset_confirmation=yes` to
skip the prompt in a script). Use this when you want to re-run
`cluster.yml` from a clean slate — e.g. after changing `kube_network_plugin`
or another bootstrap-time-only variable — without rebuilding VMs.

## Option B — Destroy the VMs entirely

Goes through `../vagrant/`, not Kubespray, and takes the whole lab (LB +
masters + workers) with it:

```bash
cd ../vagrant
vagrant destroy -f
```

Rebuilding from here means redoing the Vagrant provisioning (root README)
*and* this whole guide from doc 01.

## Which to use when

- Iterating on Kubespray `group_vars` (CNI choice, CIDRs, etc.) → **Option
  A**, much faster than rebuilding VMs.
- Something is wrong below the Kubernetes layer (corrupted disk, botched
  manual edit to `/etc/hosts`, OS-level cruft you don't trust) →
  **Option B**.
- Comparing against `../kubernetes-hardway/`'s from-scratch build on the
  *same* VMs → Option A between attempts, so you're not paying VM rebuild
  time just to switch install methods.

## Before destroying anything you might want later

If there's a kubeconfig or generated cluster state you care about, copy it
off the lab network first — `scp` from `server` to your desktop. Nothing
in `../vagrant/` or `~/kubespray` on `server` survives `vagrant destroy`.
An etcd snapshot (per
[14 — Disaster Recovery](14-disaster-recovery.md) §1) is the only thing
that lets you reconstruct actual cluster *state* — Deployments, Secrets,
ConfigMaps — afterward; a kubeconfig alone just gets you back in the door
of a cluster that no longer exists.

Once you've confirmed there's nothing left worth keeping, Option B above is
the end of this guide — you're back to bare VMs (or no VMs at all), ready
to start again from [01 — Prerequisites](01-prerequisites.md) whenever you
want.
