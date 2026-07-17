# 05 — Bootstrapping the etcd Cluster

Run on **`master1`, `master2`, and `master3`** unless a step says
otherwise. SSH in first: `ssh admin@lab-master1` (repeat for master2,
master3).

3 members gives this etcd cluster real fault tolerance — see
[the README](../README.md#etcd-fault-tolerance) for why an odd count
matters.

> **Already ran this guide with just `master1`/`master2` and now adding
> `master3` to a live cluster?** The steps below assume a fresh bootstrap
> of all three at once (`--initial-cluster-state new`). Skip to
> [§6 — Adding master3 to an already-running cluster](#6-adding-master3-to-an-already-running-cluster)
> instead — joining a live cluster needs a `member add` call first and a
> different `--initial-cluster-state`.

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

# On master3:
INTERNAL_IP=192.168.56.16
ETCD_NAME=master3
```

## 3. Create the systemd unit

The `--initial-cluster` list is identical on all three nodes — every
member needs to agree on the full membership up front.

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
  --initial-cluster master1=https://192.168.56.11:2380,master2=https://192.168.56.12:2380,master3=https://192.168.56.16:2380 \\
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

Do this on `master1`, `master2`, and `master3` roughly together — with
`--initial-cluster-state new` and all three members listed, each node will
wait to hear from its peers before forming quorum (a majority of 3, i.e.
2), so starting them one at a time with a delay is fine; the cluster just
won't report healthy until at least 2 are up.

## 5. Verify the cluster (run on any master)

```bash
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

Expect three members listed, all `started`, pointing at `.11:2380`,
`.12:2380`, and `.16:2380`.

## 6. Adding master3 to an already-running cluster

Only relevant if `master1`/`master2` etcd were already up and running
before `master3` existed — skip this section on a fresh 3-node bootstrap.

Unlike a fresh bootstrap, a running cluster must be told about the new
member **before** it starts, and the new member joins with
`--initial-cluster-state existing` instead of `new`.

**On `master1` or `master2` (an existing, already-running member):**

```bash
sudo ETCDCTL_API=3 etcdctl member add master3 \
  --peer-urls=https://192.168.56.16:2380 \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

**On `master3`:** follow steps 1-2 above (install etcd, copy certs), then
create the systemd unit exactly as in step 3 but with
`--initial-cluster-state existing` instead of `new` — the
`--initial-cluster` value stays the same full 3-member list either way:

```bash
sudo sed -i 's/--initial-cluster-state new/--initial-cluster-state existing/' \
  /etc/systemd/system/etcd.service
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
sudo systemctl status etcd --no-pager
```

Then re-run the `member list` command from step 5 (on any master) to
confirm all three show `started`. If `master3` hangs in a non-started
state, double check the `member add` call above actually completed on
`master1`/`master2` first — an etcd process refuses to join as a new
member until its peer URL is already registered in the existing cluster's
membership.

Next: [06 — Bootstrapping the Control Plane](06-bootstrapping-control-plane.md)
