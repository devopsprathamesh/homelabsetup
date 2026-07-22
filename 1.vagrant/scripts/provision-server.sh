#!/usr/bin/env bash
# Runs only on the `server` node, after provision-common.sh.
set -euo pipefail

# Install the shared lab keypair so admin can SSH into every node passwordlessly
install -d -m 700 -o admin -g admin /home/admin/.ssh
install -m 600 -o admin -g admin /tmp/lab_admin_ed25519 /home/admin/.ssh/id_ed25519
rm -f /tmp/lab_admin_ed25519

# Skip host-key prompts when first connecting to lab nodes (by IP or hostname)
cat > /home/admin/.ssh/config <<EOF
Host 192.168.56.* ${NODE_NAMES}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  User admin
EOF
chmod 600 /home/admin/.ssh/config
chown admin:admin /home/admin/.ssh/config

apt-get update -qq
apt-get install -y -qq python3 python3-pip ansible > /dev/null

if ! command -v terraform &>/dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  . /etc/os-release
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/hashicorp.list
  apt-get update -qq
  apt-get install -y -qq terraform > /dev/null
fi
