# Home Lab: HA Kubernetes on VirtualBox + Vagrant

Automates creation of a 6-node lab for a highly-available Kubernetes cluster,
running as local VirtualBox VMs and orchestrated with a single Vagrantfile.

| Node    | Role                          | IP             | vCPU | RAM  |
|---------|-------------------------------|----------------|------|------|
| server  | Load balancer / entry point   | 192.168.56.10  | 1    | 1GB  |
| master1 | Control plane (HA pair)       | 192.168.56.11  | 2    | 2GB  |
| master2 | Control plane (HA pair)       | 192.168.56.12  | 2    | 2GB  |
| node1   | Worker                        | 192.168.56.13  | 1    | 2GB  |
| node2   | Worker                        | 192.168.56.14  | 1    | 2GB  |
| node3   | Worker                        | 192.168.56.15  | 1    | 2GB  |

All nodes sit on a VirtualBox host-only private network (`192.168.56.0/24`)
and can reach each other by hostname (`server`, `master1`, ... are added to
every node's `/etc/hosts`).

## Repo layout

```
vagrant/
  Vagrantfile                 # defines all 6 machines
  scripts/provision-common.sh # shared provisioning, run on every node
vmachines/                    # per-host notes/config (currently placeholders)
```

## Prerequisites

### Hardware

- **CPU virtualization** (Intel VT-x / AMD-V) enabled in BIOS/UEFI — required
  by VirtualBox to run 64-bit guests.
- **CPU cores:** 4 physical cores minimum, 8+ recommended. The full cluster
  requests 9 vCPUs total (1+2+2+1+1+1); VirtualBox oversubscribes fine on
  4+ real cores for a dev lab, but more headroom means less contention.
- **RAM:** 16GB host minimum, 32GB comfortable. The cluster's VMs reserve
  ~11GB total; leave the rest for the host OS and VirtualBox overhead.
- **Disk:** 20GB+ free. Each linked-clone VM disk starts small (a few hundred
  MB) and grows with use; the base box image is ~1-2GB downloaded once.

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

### Current status

`server`, `master1`, `master2` have been brought up and verified. `node1-3`
are defined but not yet created — run `vagrant up` to bring them up.

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

**Not yet installed:** container runtime (containerd), `kubeadm`/`kubelet`/
`kubectl`, or a CNI plugin. The VMs are prepped for a Kubernetes install but
Kubernetes itself isn't bootstrapped yet — that's a natural next step once
you've decided on a k8s version and CNI (Calico/Flannel/Cilium).

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
- **Add/remove nodes:** add or delete entries in the array — the next
  `vagrant up` picks up the change automatically. Keep IPs inside
  `192.168.56.0/24` and unique.
- **Change the OS/box:** edit `BOX = "bento/ubuntu-24.04"` at the top.
  Any box with a VirtualBox provider works; verify it exists first with
  `curl -s -o /dev/null -w "%{http_code}" https://app.vagrantup.com/api/v1/box/<name>`
  (should return 200).
- **Change the network range:** update every `ip:` in `NODES` — they must
  all stay on the same subnet for the private network to work.
- **Add provisioning steps** (e.g. install containerd/kubeadm): extend
  `vagrant/scripts/provision-common.sh`, or add a second
  `machine.vm.provision "shell", path: "..."` block in the Vagrantfile if a
  node needs something the others don't (e.g. HAProxy only on `server`).
- **Disable linked clones** (slower but fully independent VM disks): remove
  `vb.linked_clone = true` from the provider block.

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

## Security note

`vagrant/.vagrant/` (Vagrant's local per-VM state, including auto-generated
SSH private keys for each VM) and `vmachines/.claude/settings.local.json`
(local tool settings) ended up committed to this repo. Neither is meant to
be version-controlled — `.vagrant/` is regenerated automatically by
`vagrant up` and is host-specific, and the SSH keys in it only grant access
to VMs on the local `192.168.56.0/24` host-only network, but committing
private keys is bad practice regardless. Recommended cleanup:

```bash
git rm -r --cached vagrant/.vagrant vmachines/.claude/settings.local.json
cat >> .gitignore <<EOF
.vagrant/
.claude/settings.local.json
EOF
git add .gitignore
git commit -m "Stop tracking local Vagrant state and Claude settings"
```
