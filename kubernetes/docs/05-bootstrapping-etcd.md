# 05 — Bootstrapping the etcd Cluster

Run on **both `master1` and `master2`** unless a step says otherwise. SSH
in first: `ssh admin@lab-master1` (repeat for master2).

Recall the [caveat in the README](../README.md#-known-limitation-2-node-etcd):
a 2-member etcd cluster has no fault tolerance. This still gives you a
correctly-clustered etcd — it's the topology, not the setup, that's
limited.

## 1. Download and install etcd

```bash
wget -q --show-progress --https-only \
  "https://github.com/etcd-io/etcd/releases/download/v3.5.15/etcd-v3.5.15-linux-amd64.tar.gz"

tar -xvf etcd-v3.5.15-linux-amd64.tar.gz
sudo mv etcd-v3.5.15-linux-amd64/etcd* /usr/local/bin/
etcd --version
```

## 2. Configure the etcd server

```bash
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd
sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
```

Set this node's own IP and name (run on each node with its own values):

```bash
# On master1:
INTERNAL_IP=192.168.56.11
ETCD_NAME=master1

# On master2:
INTERNAL_IP=192.168.56.12
ETCD_NAME=master2
```

## 3. Create the systemd unit

The `--initial-cluster` list is identical on both nodes — every member
needs to agree on the full membership up front.

```bash
cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/etcd-io/etcd

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-client-urls https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster master1=https://192.168.56.11:2380,master2=https://192.168.56.12:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

## 4. Start etcd

```bash
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
sudo systemctl status etcd --no-pager
```

Do this on `master1` and `master2` roughly together — with `--initial-cluster-state new`
and both members listed, each node will wait to hear from its peer before
forming quorum, so starting only one and waiting a long time before the
second is fine; it just won't report healthy until both are up.

## 5. Verify the cluster (run on either master)

```bash
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

Expect two members listed, both `started`, pointing at `.11:2380` and
`.12:2380`.

Next: [06 — Bootstrapping the Control Plane](06-bootstrapping-control-plane.md)
