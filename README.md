# Home Lab: HA Kubernetes on VirtualBox + Vagrant

Automates creation of a 7-node lab for a highly-available Kubernetes cluster,
running as local VirtualBox VMs and orchestrated with a single Vagrantfile.

| Node    | Role                          | IP             | vCPU | RAM  |
|---------|-------------------------------|----------------|------|------|
| server  | Load balancer / entry point   | 192.168.56.10  | 1    | 1GB  |
| master1 | Control plane (HA trio)       | 192.168.56.11  | 2    | 2GB  |
| master2 | Control plane (HA trio)       | 192.168.56.12  | 2    | 2GB  |
| master3 | Control plane (HA trio)       | 192.168.56.16  | 2    | 2GB  |
| node1   | Worker                        | 192.168.56.13  | 1    | 2GB  |
| node2   | Worker                        | 192.168.56.14  | 1    | 2GB  |
| node3   | Worker                        | 192.168.56.15  | 1    | 2GB  |

All nodes sit on a VirtualBox host-only private network (`192.168.56.0/24`)
and can reach each other by hostname (`server`, `master1`, ... are added to
every node's `/etc/hosts`).

## Repo layout

```
vagrant/
  Vagrantfile                 # defines all 7 machines
  scripts/provision-common.sh # shared provisioning, run on every node
  scripts/provision-server.sh # server-only: SSH key install + ansible/python3/terraform
  keys/                       # auto-generated lab-admin SSH keypair (gitignored)
vmachines/                    # per-host notes/config (currently placeholders)
```

## Prerequisites

### Hardware

- **CPU virtualization** (Intel VT-x / AMD-V) enabled in BIOS/UEFI — required
  by VirtualBox to run 64-bit guests.
- **CPU cores:** 4 physical cores minimum, 8+ recommended. The full cluster
  requests 10 vCPUs total (1+2+2+2+1+1+1); VirtualBox oversubscribes fine on
  4+ real cores for a dev lab, but more headroom means less contention.
- **RAM:** 16GB host minimum, 32GB comfortable. The cluster's VMs reserve
  ~13GB total; leave the rest for the host OS and VirtualBox overhead.
- **Disk:** 20GB+ free per node you plan to run concurrently (each VM's disk
  is capped at 30GB max, but VirtualBox allocates it dynamically — actual
  usage starts at a few hundred MB and grows with use). The base box image
  is downloaded once (~600MB).

Confirmed working on: 16-core host, 30GB RAM, 400GB+ free disk.

### Software

- **Linux host** (tested on Ubuntu 26.04 "resolute"; any recent Ubuntu/Debian
  works the same way).
- **VirtualBox** — install and confirm with `VBoxManage --version`.
  This setup was tested against VirtualBox 7.2.12.
- **Vagrant** — not in Ubuntu's default apt repos; install from HashiCorp's
  official repo:
  ```bash
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install -y vagrant
  ```
  Tested with Vagrant 2.4.9.
- **vagrant-disksize plugin** — used to cap each VM's disk at 30GB (the base
  box's disk is normally 10GB and grows as needed, but not without this
  plugin controlling the target size):
  ```bash
  vagrant plugin install vagrant-disksize
  ```
- **git**, and an SSH key registered with GitHub if you intend to push changes.

## Usage

```bash
cd vagrant

vagrant validate        # sanity-check the Vagrantfile
vagrant up               # bring up all 6 nodes
vagrant up master1        # bring up just one node
vagrant status            # see what's running
vagrant ssh master1       # log into a node
vagrant halt              # stop all nodes (keeps disks)
vagrant destroy -f        # tear down all nodes
```

## What each node gets on boot

`vagrant/scripts/provision-common.sh` runs on every node via the shell
provisioner:

- Adds all 6 lab nodes to `/etc/hosts` (idempotent — safe to re-provision).
- Disables swap at runtime and permanently in `/etc/fstab` (kubeadm requires
  swap off).
- Loads the `overlay` and `br_netfilter` kernel modules and sets the sysctls
  kubeadm/CNI plugins expect (`net.ipv4.ip_forward=1`,
  `net.bridge.bridge-nf-call-iptables=1`, etc.).
- Installs `curl`, `vim`, `net-tools`.
- Creates an `admin` user (password `x`) on every node with passwordless
  sudo and SSH password login enabled — including patching the cloud-image
  box's `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf` drop-in, which
  disables password auth by default and is read *before* the main
  `sshd_config` (sshd uses first-match-wins), so just editing the main file
  isn't enough.

  **This is intentionally weak and only acceptable because these VMs sit on
  the isolated `192.168.56.0/24` host-only network**, unreachable from
  outside the host. Do not reuse this pattern (or this password) on anything
  network-reachable. To change it, edit the `admin:x` line in
  `provision-common.sh` and re-run `vagrant provision`.
- Trusts a shared SSH public key for `admin` (see below), so `server` can
  reach every node passwordlessly.

**Not yet installed:** container runtime (containerd), `kubeadm`/`kubelet`/
`kubectl`, or a CNI plugin. The VMs are prepped for a Kubernetes install but
Kubernetes itself isn't bootstrapped yet — that's a natural next step once
you've decided on a k8s version and CNI (Calico/Flannel/Cilium).

### Keyless SSH from `server` + automation tooling

The first `vagrant up` generates an ED25519 keypair at `vagrant/keys/`
(gitignored — never commit it). The public half is trusted by every node's
`admin` user; the private half is installed only on `server`
(`vagrant/scripts/provision-server.sh`, via a `file` provisioner + a
server-only shell provisioner), along with an SSH client config that skips
host-key prompts for the lab's nodes (by hostname and by
`192.168.56.0/24` IP). From `server`, as `admin`:

```bash
ssh admin@master1   # or any node name / 192.168.56.x — no password, no prompt
```

`server` also gets `python3`, `ansible` (via apt), and `terraform` (via
HashiCorp's apt repo, same source used to install Vagrant on the host)
installed, so it can act as an Ansible/Terraform control node against the
rest of the cluster. No Ansible inventory or Terraform config is set up yet
— just the tooling and passwordless access to build on.

If you ever want a fresh keypair (e.g. suspected compromise), delete
`vagrant/keys/` and re-run `vagrant provision` on every node — a new key
will be generated and redistributed automatically.

### Keyless SSH from this desktop

The Vagrantfile also reads `~/.ssh/id_ed25519.pub` on the host (if present)
and trusts it on every node's `admin` user alongside the lab keypair, so you
can SSH in directly from this machine too, not just from `server`:

```bash
ssh admin@lab-server
ssh admin@lab-master1
# ...lab-master2, lab-master3, lab-node1, lab-node2, lab-node3
```

The `lab-*` hostnames are entries this setup added to the desktop's
`/etc/hosts` (192.168.56.10-16) — prefixed with `lab-` because this host
already had an unrelated `server` entry (192.168.29.47) that would otherwise
collide. If you SSH in with a different key than `~/.ssh/id_ed25519`, edit
`HOST_PUBKEY_PATH` in the Vagrantfile and re-run `vagrant provision`.

**Note:** these `lab-*` host entries live only on this desktop's
`/etc/hosts` — they aren't part of the Vagrantfile/provisioning and won't
follow you to another machine. If you add a node, re-run the same `sudo`
block manually (or script it) to add its `lab-<name>` entry here too.

## What you can change

Everything node-related lives in the `NODES` array at the top of the
Vagrantfile:

```ruby
NODES = [
  { name: "server",  ip: "192.168.56.10", cpus: 1, memory: 1024 },
  { name: "master1", ip: "192.168.56.11", cpus: 2, memory: 2048 },
  ...
]
```

- **Resize a node:** edit its `cpus:`/`memory:` values. Note kubeadm hard-
  requires `cpus: 2` on master nodes (`kubeadm init` fails preflight checks
  below that); worker nodes and the LB can go as low as 1.
- **Add/remove nodes:** add or delete entries in the array, then
  `vagrant up <name>` for the new one. Keep IPs inside `192.168.56.0/24`
  and unique. After adding a node, also re-run `vagrant provision` on the
  *existing* nodes so their `/etc/hosts` (and `server`'s SSH `Host` pattern,
  which is built dynamically from `NODES`) picks up the new node — otherwise
  they won't be able to resolve or SSH to it by name yet. If you SSH from
  this desktop, add a matching `lab-<name>` line to `/etc/hosts` too (see
  Keyless SSH section below).
- **Change the OS/box:** edit `BOX = "cloud-image/ubuntu-24.04"` at the top.
  Any box with a VirtualBox provider works; verify it exists first with
  `curl -s -o /dev/null -w "%{http_code}" https://app.vagrantup.com/api/v1/box/<name>`
  (should return 200). Prefer cloud-image-style boxes (small native disk that
  grows on demand) over boxes like `bento/*` that bake in a fixed 64GB
  disk — VirtualBox can grow a disk but cannot shrink one, so a box with a
  disk already larger than your target size can't be capped down.
- **Change the disk size cap:** edit `machine.disksize.size = "30GB"` in the
  Vagrantfile (requires the `vagrant-disksize` plugin, see Prerequisites).
  Only increases are possible on already-created VMs; shrinking requires
  `vagrant destroy` + `vagrant up` to rebuild from the box.
- **Change the network range:** update every `ip:` in `NODES` — they must
  all stay on the same subnet for the private network to work.
- **Add provisioning steps** (e.g. install containerd/kubeadm): extend
  `vagrant/scripts/provision-common.sh`, or add a second
  `machine.vm.provision "shell", path: "..."` block in the Vagrantfile if a
  node needs something the others don't (e.g. HAProxy only on `server`).
- **Switch to linked clones** (faster VM creation, much less disk usage, at
  the cost of a shared "base" VM appearing in VirtualBox that every node's
  disk depends on): add `vb.linked_clone = true` to the provider block.
  Currently using full clones instead — see the switching note below.

## Notable issue hit and fixed during setup

The provisioning script was originally written as an inline Ruby heredoc
(`<<-SHELL`) containing a nested bash heredoc (`<<-EOF`) for writing
`/etc/hosts`. Because Ruby's `<<-` heredoc preserves leading whitespace
(unlike bash's `<<-`, which only strips literal tabs), the inner heredoc's
indented terminator line never matched, so the bash heredoc swallowed the
rest of the script as literal text into `/etc/hosts` — silently skipping the
swap/sysctl/kernel-module steps and corrupting the hosts file. Fixed by
moving provisioning into a real script file
(`vagrant/scripts/provision-common.sh`), referenced from the Vagrantfile via
`path:` instead of an inline heredoc, with `HOSTS_ENTRIES` passed in as an
environment variable. Verified fixed with a full smoke test (swap off,
sysctls set, kernel modules loaded, `/etc/hosts` correct, ping between
nodes) before scaling up to the full cluster.

`provision-server.sh` originally hardcoded the node names in `admin`'s SSH
client config (`Host 192.168.56.* server master1 master2 node1 node2
node3`) instead of deriving them from `NODES`. It worked until `master3` was
added — `ssh master3` from `server` then failed host-key verification
because `master3` wasn't in that hardcoded list (connecting by IP still
worked, since `192.168.56.*` did match). Fixed by passing a `NODE_NAMES`
environment variable (built from `NODES.map { |n| n[:name] }`) into
`provision-server.sh` and interpolating it into the `Host` line, so adding a
node to `NODES` now automatically covers it — no separate list to remember
to update.

## Linked clones → full clones

Initially used `vb.linked_clone = true`, which is faster to create and uses
far less disk (each node stores only its diff from a shared base image).
Switched to full clones (the VirtualBox provider's default — the line was
removed rather than set to `false`) because the shared "base" VM that
linked clones leave behind in the VirtualBox GUI was confusing without
context. Trade-off: node creation is slower and each node reserves its full
30GB disk allocation independently, but every node is now fully
self-contained with no shared dependency. To switch back, add
`vb.linked_clone = true` to the provider block in the Vagrantfile.

## Security note

The initial commit accidentally included `vagrant/.vagrant/` (Vagrant's
local per-VM state, including auto-generated SSH private keys) and
`vmachines/.claude/settings.local.json` (local tool settings). This was
fixed in a follow-up commit — both are now untracked via `.gitignore` and
removed from the current snapshot. The old commit still has them in git
history; the exposed SSH keys only grant access to VMs on the local
`192.168.56.0/24` host-only network (not reachable remotely), so the
practical risk is low, but a full history rewrite (`git filter-repo` +
force-push) would be needed to remove them entirely if that matters for
your use case.

### Switching base box: bento → cloud-image

The box was changed from `bento/ubuntu-24.04` to `cloud-image/ubuntu-24.04`
specifically to support the 30GB disk cap — bento's box bakes in a fixed
64GB LVM-partitioned disk that VirtualBox cannot shrink, while Canonical's
cloud image starts at 10GB and grows cleanly to whatever size
`vagrant-disksize` requests, with a plain GPT partition table (no LVM) that
cloud-init auto-resizes on first boot.
