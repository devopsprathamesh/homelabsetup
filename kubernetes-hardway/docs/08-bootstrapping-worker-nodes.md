# 08 — Bootstrapping Worker Nodes

Run on **each of `node1`, `node2`, `node3`**. Steps below use `node1` /
`10.200.0.0/24` as the example — substitute per node:

| Node  | Pod CIDR       |
|-------|----------------|
| node1 | 10.200.0.0/24  |
| node2 | 10.200.1.0/24  |
| node3 | 10.200.2.0/24  |

```bash
POD_CIDR=10.200.0.0/24   # node1; use 10.200.1.0/24 on node2, 10.200.2.0/24 on node3
```

## 1. Install OS-level dependencies

```bash
sudo apt update
sudo apt install -y socat conntrack ipset
```

`socat` enables the `kubectl port-forward` container namespace trick;
`conntrack`/`ipset` are required by `kube-proxy`'s iptables mode.

## 2. Disable swap (belt-and-suspenders check)

Already handled by Vagrant provisioning, but kubelet will refuse to start
otherwise, so verify:

```bash
swapon --show   # must print nothing
```

## 3. Download worker binaries

```bash
wget -q --show-progress --https-only \
  https://github.com/containernetworking/plugins/releases/download/v1.5.1/cni-plugins-linux-amd64-v1.5.1.tgz \
  https://github.com/containerd/containerd/releases/download/v1.7.22/containerd-1.7.22-linux-amd64.tar.gz \
  https://github.com/opencontainers/runc/releases/download/v1.1.14/runc.amd64 \
  https://dl.k8s.io/v1.31.0/bin/linux/amd64/kubectl \
  https://dl.k8s.io/v1.31.0/bin/linux/amd64/kube-proxy \
  https://dl.k8s.io/v1.31.0/bin/linux/amd64/kubelet
```

## 4. Install binaries

```bash
sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes \
  /etc/containerd \
  /var/lib/containerd

sudo mkdir -p containerd
tar -xvf containerd-1.7.22-linux-amd64.tar.gz -C containerd
sudo mv containerd/bin/* /bin/

sudo tar -xvf cni-plugins-linux-amd64-v1.5.1.tgz -C /opt/cni/bin/

chmod +x kubectl kube-proxy kubelet runc.amd64
sudo mv kubectl kube-proxy kubelet /usr/local/bin/
sudo mv runc.amd64 /usr/local/bin/runc
```

## 5. Configure CNI networking

This is the "hard way" CNI setup: a plain `bridge` + `host-local` IPAM
plugin per node, each owning a distinct `/24` out of the overall
`10.200.0.0/16` pod network. There's no overlay and no cross-node route
propagation daemon — that gap gets closed manually in
[10 — Pod Network Routes](10-pod-network-routes.md).

```bash
cat <<EOF | sudo tee /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "1.0.0",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

cat <<EOF | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "1.0.0",
    "name": "lo",
    "type": "loopback"
}
EOF
```

## 6. Configure containerd

```bash
sudo mkdir -p /etc/containerd

cat <<EOF | sudo tee /etc/containerd/config.toml
version = 2
[plugins."io.containerd.grpc.v1.cri"]
  [plugins."io.containerd.grpc.v1.cri".containerd]
    snapshotter = "overlayfs"
    [plugins."io.containerd.grpc.v1.cri".containerd.default_runtime]
      runtime_type = "io.containerd.runc.v2"
      [plugins."io.containerd.grpc.v1.cri".containerd.default_runtime.options]
        SystemdCgroup = true
EOF

cat <<'EOF' | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF
```

## 7. Configure kubelet

```bash
NODE_NAME=node1   # node2 / node3 on those hosts

sudo cp ${NODE_NAME}-key.pem ${NODE_NAME}.pem /var/lib/kubelet/
sudo cp ${NODE_NAME}.kubeconfig /var/lib/kubelet/kubeconfig
sudo cp ca.pem /var/lib/kubernetes/

cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
cgroupDriver: systemd
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${NODE_NAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${NODE_NAME}-key.pem"
EOF

cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

`resolvConf` points at `systemd-resolved`'s stub file since Ubuntu 24.04
uses it by default — pods need a real upstream resolver, not the
`127.0.0.53` stub, to avoid resolution loops once CoreDNS is up. If
`/run/systemd/resolve/resolv.conf` doesn't exist on your image, check
`systemctl status systemd-resolved` and fall back to `/etc/resolv.conf` if
resolved isn't running.

`cgroupDriver: systemd` matches containerd's `SystemdCgroup = true` set
below — kubelet 1.28+ auto-detects this from the CRI runtime if omitted,
but setting it explicitly avoids depending on that detection working.

No `--image-credential-provider-bin-dir`/`-config` flags here: they're only
needed for exec-based registry auth plugins (ECR, GCR, etc.), and setting
`-bin-dir` without a matching `-config` — or pointing it at a directory
that doesn't exist — makes kubelet call `os.Exit(1)` during startup
(`RegisterCredentialProviderPlugins` in
`pkg/kubelet/kuberuntime/kuberuntime_manager.go` fails closed). Nothing in
this lab needs it; leave both flags out.

## 8. Configure kube-proxy

```bash
sudo cp kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
EOF

cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

## 9. Start everything

```bash
sudo systemctl daemon-reload
sudo systemctl enable containerd kubelet kube-proxy
sudo systemctl start containerd kubelet kube-proxy
sudo systemctl status containerd kubelet kube-proxy --no-pager
```

## 10. Repeat for node2 and node3

Same steps, with `POD_CIDR=10.200.1.0/24` / `NODE_NAME=node2` on `node2`,
and `POD_CIDR=10.200.2.0/24` / `NODE_NAME=node3` on `node3`. The `.kubeconfig`
and `.pem`/`-key.pem` files referenced above are the per-node ones scp'd in
[02](02-certificate-authority.md) and [03](03-kubernetes-configuration-files.md) —
make sure you're using each node's own files, not another node's.

## 11. Verify

**Run on:** any master (using its local `admin.kubeconfig` from
[03](03-kubernetes-configuration-files.md)), or the client machine once
[09](09-configuring-kubectl.md) is done.

```bash
kubectl get nodes --kubeconfig admin.kubeconfig
```

Expect `node1`, `node2`, `node3` listed with `STATUS Ready` (may take
10-20s after kubelet starts — it needs a working CNI config to flip out of
`NotReady`).

Next: [09 — Configuring kubectl](09-configuring-kubectl.md)
