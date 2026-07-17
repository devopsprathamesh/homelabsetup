#!/usr/bin/env bash
# Common provisioning for every lab node. HOSTS_ENTRIES is passed in via env.
set -euo pipefail

# Resolve every lab node by hostname (idempotent: strip old block first)
sed -i '/# lab-nodes-start/,/# lab-nodes-end/d' /etc/hosts
{
  echo "# lab-nodes-start"
  echo "$HOSTS_ENTRIES"
  echo "# lab-nodes-end"
} >> /etc/hosts

# Kubernetes prerequisites: swap must be off, permanently
swapoff -a
sed -i -E '/[[:space:]]swap[[:space:]]/ s/^/#/' /etc/fstab

# Kernel modules + sysctl required for pod networking
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null

apt-get update -qq
apt-get install -y -qq curl vim net-tools > /dev/null
