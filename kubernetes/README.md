# Kubernetes the Hard Way — this lab

A from-scratch Kubernetes install (no kubeadm, no installer scripts) targeting
the 6 VMs already provisioned by [`../vagrant/`](../vagrant/): every control
plane and node component is a hand-built binary running as a systemd unit,
following the shape of Kelsey Hightower's [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way),
adapted to this lab's topology.

## Topology

| Node    | Role                        | IP            | vCPU | RAM  |
|---------|-----------------------------|---------------|------|------|
| server  | HAProxy load balancer       | 192.168.56.10 | 1    | 1GB  |
| master1 | Control plane + etcd        | 192.168.56.11 | 2    | 2GB  |
| master2 | Control plane + etcd        | 192.168.56.12 | 2    | 2GB  |
| node1   | Worker                      | 192.168.56.13 | 1    | 2GB  |
| node2   | Worker                      | 192.168.56.14 | 1    | 2GB  |
| node3   | Worker                      | 192.168.56.15 | 1    | 2GB  |

All nodes: Ubuntu 24.04, `admin` user, passwordless sudo, passwordless SSH
from `server` and from the desktop host (see [../README.md](../README.md)).
Network: `192.168.56.0/24`, host-only, not reachable outside the host.

```
                        ┌─────────────────┐
                        │  server (LB)    │
                        │  HAProxy :6443  │
                        └────────┬────────┘
                    ┌────────────┴────────────┐
                    ▼                         ▼
          ┌──────────────────┐      ┌──────────────────┐
          │ master1           │      │ master2           │
          │ etcd + apiserver  │◄────►│ etcd + apiserver  │
          │ controller-mgr    │      │ controller-mgr    │
          │ scheduler         │      │ scheduler         │
          └──────────────────┘      └──────────────────┘
                    ▲                         ▲
        ┌───────────┼─────────────────────────┼───────────┐
        ▼           ▼                         ▼           ▼
   ┌─────────┐ ┌─────────┐               ┌─────────┐ ┌─────────┐
   │ node1   │ │ node2   │               │ node3   │ │  ...    │
   │ kubelet │ │ kubelet │               │ kubelet │ │         │
   │kube-proxy│ │kube-proxy│              │kube-proxy│ │         │
   │containerd│ │containerd│              │containerd│ │         │
   └─────────┘ └─────────┘               └─────────┘ └─────────┘
```

## ⚠️ Known limitation: 2-node etcd

etcd uses Raft consensus, which needs a **majority** of members alive to
accept writes. With 2 members, losing either `master1` or `master2` loses
quorum — the surviving node cannot serve writes even though it's healthy.
Two control planes give you API-server-level redundancy behind the load
balancer (reads/cached data still work, and you avoid a single point of
failure for the API frontend), but **not** true etcd fault tolerance. Real
HA etcd wants an odd number ≥ 3. If you later add a 3rd control-plane node,
re-run [docs/05-bootstrapping-etcd.md](docs/05-bootstrapping-etcd.md) with
the updated member list.

## Versions used in this guide

Pin these; every command below assumes them. Bump deliberately, not
mid-guide.

| Component        | Version   |
|-------------------|----------|
| Kubernetes         | v1.31.0 |
| etcd               | v3.5.15 |
| containerd         | v1.7.22 |
| runc               | v1.1.14 |
| CNI plugins        | v1.5.1  |
| cfssl / cfssljson  | v1.6.5  |
| CoreDNS            | v1.11.3 |

## Guide order

1. [Prerequisites](docs/01-prerequisites.md) — client tools, node prep sanity checks
2. [Certificate Authority](docs/02-certificate-authority.md) — CA + all component certs
3. [Kubernetes Configuration Files](docs/03-kubernetes-configuration-files.md) — kubeconfigs
4. [Data Encryption Config](docs/04-data-encryption-config.md) — secrets-at-rest key
5. [Bootstrapping etcd](docs/05-bootstrapping-etcd.md) — on master1 + master2
6. [Bootstrapping the Control Plane](docs/06-bootstrapping-control-plane.md) — apiserver, controller-manager, scheduler
7. [Load Balancer](docs/07-load-balancer.md) — HAProxy on `server`
8. [Bootstrapping Worker Nodes](docs/08-bootstrapping-worker-nodes.md) — containerd, kubelet, kube-proxy
9. [Configuring kubectl](docs/09-configuring-kubectl.md) — remote admin access
10. [Pod Network Routes](docs/10-pod-network-routes.md) — static routing between node CIDRs
11. [DNS Cluster Add-on](docs/11-dns-cluster-addon.md) — CoreDNS
12. [Smoke Test](docs/12-smoke-test.md) — prove it all works
13. [Cleanup](docs/13-cleanup.md) — tear down / reset

Work through them in order — later steps assume files and state from earlier
ones. Run each command block on the node(s) named in its heading.
