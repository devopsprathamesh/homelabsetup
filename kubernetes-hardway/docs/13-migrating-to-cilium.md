# 13 — Migrating from kube-proxy + Manual CNI to Cilium (with Hubble)

Prerequisite: a cluster that's passed [12 — Smoke Test](12-smoke-test.md).
This doc rips out two pieces built earlier — the hand-rolled `bridge` +
`host-local` CNI config ([08](08-bootstrapping-worker-nodes.md) §5) and
`kube-proxy` ([08](08-bootstrapping-worker-nodes.md) §8) — and replaces
both with Cilium's eBPF datapath, which also gets you Hubble (flow-level
network observability) for free.

Run everything below from your **client machine**, using the kubeconfig
from [09](09-configuring-kubectl.md), unless a step says otherwise.

## Why kube-proxy replacement, not just a CNI swap

Cilium can run two ways: alongside `kube-proxy` (Cilium only replaces the
CNI plugin) or as a full kube-proxy replacement (Cilium's eBPF also
handles Service load-balancing). This guide uses the latter — mainly
because it's what makes Hubble worth having: with kube-proxy replacement,
Cilium is what routes Service traffic, so Hubble can show you flows
*attributed to Services* (`pod-a → Service nginx → pod-b`), not just raw
pod-to-pod IPs. Without it, Hubble only sees what the CNI touches, which
is a much thinner picture.

## Why VXLAN, not native routing

All 6 masters/nodes sit on one flat L2 subnet (`192.168.56.0/24`), so
native routing (no encapsulation) is possible here, but it requires
getting `auto-direct-node-routes` and the interface name exactly right
for not much benefit at lab scale. VXLAN is Cilium's default, needs zero
manual routing, and is what the rest of this doc assumes.

## The chicken-and-egg kube-proxy replacement usually has — already solved

Cilium's kube-proxy replacement needs to reach the API server directly
during its own bootstrap, *before* Service routing exists (it can't use
the `kubernetes` Service's ClusterIP — that's exactly what it's about to
start providing). Normally this means inventing a stable non-Service
endpoint. Here you already have one: the HAProxy load balancer from
[07](07-load-balancer.md), plain TCP passthrough on `192.168.56.10:6443`,
already used by every kubeconfig in this guide. Point Cilium at that.

## 1. Install the Cilium CLI (client machine)

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --remote-name-all \
  "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz"
sudo tar -xzvf cilium-linux-amd64.tar.gz -C /usr/local/bin
rm cilium-linux-amd64.tar.gz
cilium version --client
```

## 2. Install Helm (client machine)

The Cilium chart is what actually installs Cilium — hand-authoring the
equivalent raw manifests isn't practical (it's a large, versioned chart
with a CRD set), same reasoning as downloading prebuilt `kubectl`/`etcd`
binaries earlier in this guide rather than compiling from source.

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod +x get_helm.sh
./get_helm.sh
rm get_helm.sh
helm version
```

## 3. Remove the old CNI config and kube-proxy from every node

**Run on:** `node1`, `node2`, `node3` — repeat on each.

```bash
sudo rm -f /etc/cni/net.d/10-bridge.conf /etc/cni/net.d/99-loopback.conf

sudo systemctl stop kube-proxy
sudo systemctl disable kube-proxy
sudo /usr/local/bin/kube-proxy --cleanup   # removes kube-proxy's iptables rules
sudo ip link delete cnio0 2>/dev/null || true
```

`cnio0` is the bridge the old CNI config created — deleting it is harmless
even if it's already gone (`|| true` covers that). Cilium creates its own
`cilium_host`/`cilium_net`/`cilium_vxlan` interfaces separately.

## 4. Remove the manual pod-network routes

If you followed [10 — Pod Network Routes](10-pod-network-routes.md),
those static routes now conflict with Cilium's VXLAN overlay (both
claiming to know how to reach the same pod CIDRs) — remove them.

**Run on:** all 7 VMs — `node1`, `node2`, `node3`, `master1`, `master2`,
`master3`, `server` — whichever still have the persisted netplan file:

```bash
sudo rm -f /etc/netplan/90-pod-routes.yaml
sudo netplan apply
```

Any routes added with a plain `ip route add` (not persisted via netplan)
don't need manual removal — they won't survive the next reboot anyway,
but if you want them gone immediately: `sudo ip route del <cidr> via <ip>`
per route from [10](10-pod-network-routes.md)'s table.

## 5. Install Cilium

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

CILIUM_VERSION=1.16.5   # check `helm search repo cilium/cilium --versions` for a newer 1.16.x if this is stale

helm install cilium cilium/cilium --version ${CILIUM_VERSION} \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=192.168.56.10 \
  --set k8sServicePort=6443 \
  --set ipam.mode=kubernetes \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true
```

`ipam.mode=kubernetes` tells Cilium to read each node's pod CIDR from
`node.Spec.PodCIDR` — already being assigned by `kube-controller-manager`
(`--allocate-node-cidrs=true --cluster-cidr=10.200.0.0/16` from
[06](06-bootstrapping-control-plane.md)) — rather than Cilium allocating
its own ranges (`ipam.mode=cluster-pool`), which would race with
controller-manager for the same job. The exact node → CIDR mapping from
[01](01-prerequisites.md)'s reference table no longer matters once
Cilium is managing it.

## 6. Verify

```bash
cilium status --wait
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl get nodes
```

Expect every `cilium-*` pod `Running`, `cilium status` reporting
`kube-proxy replacement: True`, and all 6 nodes still `Ready`.

Re-run the same checks [12 — Smoke Test](12-smoke-test.md) did — a
Deployment, a Service, cross-node pod-to-pod traffic, CoreDNS resolution —
to confirm nothing regressed:

```bash
kubectl create deployment cilium-check --image=nginx --replicas=3
kubectl expose deployment cilium-check --port=80
kubectl wait --for=condition=Ready pod -l app=cilium-check --timeout=60s
kubectl run test-client --image=busybox --restart=Never --command -- sleep 3600
kubectl wait --for=condition=Ready pod/test-client --timeout=30s
kubectl exec test-client -- wget -qO- cilium-check.default.svc.cluster.local
kubectl delete deployment cilium-check
kubectl delete service cilium-check
kubectl delete pod test-client
```

Optional, much more thorough (spins up test pods across every node,
takes a few minutes): `cilium connectivity test`.

## 7. Using Hubble

Two ways to look at flows, both via a port-forward to Hubble Relay that
the `cilium` CLI manages for you:

**From the terminal (works over plain SSH, no browser needed):**

```bash
cilium hubble port-forward &
hubble observe --follow
```

`hubble observe` streams live flow logs — pod IPs, Service names when
kube-proxy replacement is on, verdict (`FORWARDED`/`DROPPED`), L4/L7
protocol. Add `--namespace default` or `--pod cilium-check` to filter.

**Hubble UI (a web dashboard)** — since `server` is a headless VM you SSH
into rather than a desktop with a browser, bind the port-forward to all
interfaces so you can reach it over the host-only network instead of just
`server`'s own loopback:

```bash
kubectl port-forward -n kube-system svc/hubble-ui --address 0.0.0.0 12000:80
```

Then, from your actual desktop's browser: `http://192.168.56.10:12000`.

## What this changes for a future fresh install

If you're running this whole guide again from scratch and want Cilium
from the start rather than migrating into it: skip
[08](08-bootstrapping-worker-nodes.md) §5 (CNI config) and §8
(kube-proxy) entirely, skip [10](10-pod-network-routes.md) entirely, and
run this doc right after [09](09-configuring-kubectl.md) instead of after
12 — nothing else in the guide (etcd, control plane, DNS, HA deep dive)
depends on which CNI/Service-routing layer is underneath.

Next: [14 — High Availability Deep Dive](14-ha-deep-dive.md) — everything
in it still applies; none of Cilium's changes touch etcd/control-plane HA.
