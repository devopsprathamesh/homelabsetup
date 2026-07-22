# 01 — Prerequisites

## Where to run things

Two kinds of steps in this guide:

- **Control node** — `server` (192.168.56.10). This is where Kubespray's
  Ansible playbooks actually execute from. It already has passwordless SSH
  and sudo to every other node (set up by `vagrant/scripts/provision-server.sh`).
- **Desktop** — wherever you're reading this from. Used only to `ssh` into
  `server` to drive everything else.

```bash
ssh admin@lab-server
```

Every command block below is written to run **on `server`**, as `admin`,
unless stated otherwise.

## 1. Confirm the VMs are up and reachable

```bash
VBoxManage list runningvms
```

You should see all 7: `server`, `master1`, `master2`, `master3`, `node1`,
`node2`, `node3`. If any are missing:

```bash
cd ../vagrant && vagrant up
```

## 2. Confirm Ansible connectivity from `server`

```bash
ssh admin@lab-server
cd ~/ansible
ansible all -m ping
```

All 7 hosts (`server` + 3 masters + 3 workers) should reply `pong`. If a
host fails, check `../vagrant/keys/` still matches what's trusted on that
node (see root README's "Keyless SSH" section) — Kubespray needs this same
passwordless access to every `kube_control_plane` / `kube_node` host.

## 3. Confirm kubeadm/kubelet prerequisites are already met

`vagrant/scripts/provision-common.sh` did this at VM creation time — verify
it's still true (a live kubelet refuses to start with swap on, and CNI
plugins need the bridge/overlay sysctls):

```bash
ansible k8s_cluster -m shell -a "swapon --show; sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables; lsmod | grep -E 'overlay|br_netfilter'"
```

Expect: `swapon --show` prints nothing, both sysctls read `= 1`, and both
kernel modules are listed as loaded.

## 4. Confirm control-node software versions

Kubespray pins exact `ansible`/Python package versions in its
`requirements.txt` and won't reliably run on arbitrary versions — this is
why the next doc builds an isolated virtualenv rather than using the
`ansible` apt package already on `server`.

```bash
lsb_release -a          # expect Ubuntu 24.04.x LTS
python3 --version       # expect 3.12.x
python3 -m venv --help  # must not error; if it does:
                         #   sudo apt-get install -y python3.12-venv
git --version           # any recent git; 2.43+ confirmed working
```

## 5. Confirm outbound internet access from `server`

Kubespray's playbooks pull container images and, during control-node setup,
`pip`/`git` need to reach GitHub and PyPI:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://github.com
curl -s -o /dev/null -w '%{http_code}\n' https://pypi.org
```

Both should print `200`. If `server` is air-gapped in your environment,
Kubespray supports an offline mode (local container registry + package
mirror) — out of scope for this lab guide.

## 6. Resource sanity check

```bash
ansible k8s_cluster -m shell -a "nproc; free -h | grep Mem"
```

Masters are 2 vCPU / 2GB RAM each — this is the *bare minimum* kubeadm's
preflight checks allow, not a comfortable production number. It's enough to
get a working HA control plane in a lab; see
[11 — Security Hardening](11-security-hardening.md) for what to bump before
calling this "production" in anything but pattern.

Next: [02 — Control Node Setup](02-control-node-setup.md)
