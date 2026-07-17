# 01 — Prerequisites

## Where to run things

Two kinds of steps in this guide:

- **Client machine** — wherever you run `ssh`/`scp` from (your desktop, or
  `server` acting as a jump host). This is where certs and kubeconfigs get
  *generated*, then distributed out to the nodes that need them.
- **Node steps** — run directly on the named VM (`master1`, `node1`, etc.),
  usually via `ssh admin@<node>`.

This guide assumes you're driving from your desktop, which already has
passwordless SSH to every node (see the root [README](../../README.md)).
Substitute `server` for "client machine" if you'd rather drive from inside
the lab network.

## 1. Confirm connectivity to every node

```bash
for h in lab-server lab-master1 lab-master2 lab-master3 lab-node1 lab-node2 lab-node3; do
  echo "== $h =="; ssh admin@$h 'hostname; uname -r'
done
```

If `lab-*` hostnames aren't resolving, use the raw IPs instead
(`192.168.56.10-15`, plus `192.168.56.16` for `master3`), or check
`/etc/hosts` on your desktop (see root README's "Keyless SSH from this
desktop" section — note `master3` was added after that section's `sudo`
block ran, so you may need to add its `lab-master3` line by hand).

## 2. Confirm swap is off and sysctls are set

`vagrant/scripts/provision-common.sh` already did this at VM creation time,
but verify — a live kubelet will refuse to start with swap on:

```bash
for h in lab-master1 lab-master2 lab-master3 lab-node1 lab-node2 lab-node3; do
  echo "== $h =="
  ssh admin@$h 'swapon --show; sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables'
done
```

Expect `swapon --show` to print nothing, and both sysctls to read `= 1`.

## 3. Install client-side tools (on your client machine)

```bash
cd /tmp
curl -L -o cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssl_1.6.5_linux_amd64
curl -L -o cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssljson_1.6.5_linux_amd64
chmod +x cfssl cfssljson
sudo mv cfssl cfssljson /usr/local/bin/

curl -L -o kubectl https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

cfssl version
kubectl version --client
```

## 4. Working directory

Everything generated in this guide (certs, keys, kubeconfigs) is created
under a single scratch directory on the client machine, then scp'd out to
nodes. Create it now:

```bash
mkdir -p ~/k8s-the-hard-way && cd ~/k8s-the-hard-way
```

Run every command block in the rest of this guide's "client machine"
sections from inside `~/k8s-the-hard-way` unless stated otherwise.

## 5. Node/IP reference

Keep this handy — it's reused verbatim in cert SANs, etcd member lists, and
kubeconfig server URLs throughout the guide.

```
LB_IP=192.168.56.10       # server
MASTER1_IP=192.168.56.11
MASTER2_IP=192.168.56.12
MASTER3_IP=192.168.56.16
NODE1_IP=192.168.56.13
NODE2_IP=192.168.56.14
NODE3_IP=192.168.56.15

SERVICE_CIDR=10.32.0.0/24     # ClusterIP range
CLUSTER_DNS_IP=10.32.0.10     # CoreDNS ClusterIP, must be inside SERVICE_CIDR
POD_CIDR=10.200.0.0/16        # overall pod network
NODE1_POD_CIDR=10.200.0.0/24
NODE2_POD_CIDR=10.200.1.0/24
NODE3_POD_CIDR=10.200.2.0/24
```

Next: [02 — Certificate Authority](02-certificate-authority.md)
