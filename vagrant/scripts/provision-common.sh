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

# Lab admin user: passwordless sudo + password SSH login
# (this box already has a system group named "admin"; reuse it as primary group)
if ! id admin &>/dev/null; then
  useradd -m -s /bin/bash -g admin admin
fi
echo "admin:x" | chpasswd
usermod -aG sudo admin
echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-admin
chmod 440 /etc/sudoers.d/90-admin

sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
# cloud-image boxes ship a drop-in that disables password auth and is
# included ahead of the main file (sshd uses first-match-wins), so patch it too
if [ -d /etc/ssh/sshd_config.d ]; then
  sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
fi
systemctl restart ssh

# Trust the shared lab keypair so `server` can SSH in as admin passwordlessly,
# plus the host desktop's own key so you can SSH in directly from there too
install -d -m 700 -o admin -g admin /home/admin/.ssh
touch /home/admin/.ssh/authorized_keys
grep -qxF "$LAB_ADMIN_PUBKEY" /home/admin/.ssh/authorized_keys || echo "$LAB_ADMIN_PUBKEY" >> /home/admin/.ssh/authorized_keys
if [ -n "${HOST_ADMIN_PUBKEY:-}" ]; then
  grep -qxF "$HOST_ADMIN_PUBKEY" /home/admin/.ssh/authorized_keys || echo "$HOST_ADMIN_PUBKEY" >> /home/admin/.ssh/authorized_keys
fi
chmod 600 /home/admin/.ssh/authorized_keys
chown admin:admin /home/admin/.ssh/authorized_keys
