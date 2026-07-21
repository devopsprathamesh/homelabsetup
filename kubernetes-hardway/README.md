# Kubernetes the Hard Way — this lab

A from-scratch Kubernetes install (no kubeadm, no installer scripts) targeting
the 7 VMs already provisioned by [`../vagrant/`](../vagrant/): every control
plane and node component is a hand-built binary running as a systemd unit,
following the shape of Kelsey Hightower's [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way),
adapted to this lab's topology.

## Topology

| Node    | Role                        | IP            | vCPU | RAM  |
|---------|-----------------------------|---------------|------|------|
| server  | HAProxy load balancer       | 192.168.56.10 | 1    | 1GB  |
| master1 | Control plane + etcd        | 192.168.56.11 | 2    | 2GB  |
| master2 | Control plane + etcd        | 192.168.56.12 | 2    | 2GB  |
| master3 | Control plane + etcd        | 192.168.56.16 | 2    | 2GB  |
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
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
          ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
          │ master1           │ │ master2           │ │ master3           │
          │ etcd + apiserver  │◄►│ etcd + apiserver  │◄►│ etcd + apiserver  │
          │ controller-mgr    │ │ controller-mgr    │ │ controller-mgr    │
          │ scheduler         │ │ scheduler         │ │ scheduler         │
          └──────────────────┘ └──────────────────┘ └──────────────────┘
                    ▲                  ▲                  ▲
                    │                  │                  │
          ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
          │ node1             │ │ node2             │ │ node3             │
          │ kubelet           │ │ kubelet           │ │ kubelet           │
          │ kube-proxy        │ │ kube-proxy        │ │ kube-proxy        │
          │ containerd        │ │ containerd        │ │ containerd        │
          └──────────────────┘ └──────────────────┘ └──────────────────┘
```

## etcd fault tolerance

With `master3` added, etcd now has 3 members — Raft consensus needs a
**majority** to accept writes, so a 3-member cluster tolerates losing
**any one** node (2 of 3 still form quorum) while staying fully writable.
That's genuine HA, unlike the earlier 2-master topology (documented in git
history) where losing either master lost quorum entirely. Going forward,
always keep the control-plane count odd (3, 5, ...) — an even number adds a
node without adding tolerance.

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
5. [Bootstrapping etcd](docs/05-bootstrapping-etcd.md) — on master1 + master2 + master3
6. [Bootstrapping the Control Plane](docs/06-bootstrapping-control-plane.md) — apiserver, controller-manager, scheduler
7. [Load Balancer](docs/07-load-balancer.md) — HAProxy on `server`
8. [Bootstrapping Worker Nodes](docs/08-bootstrapping-worker-nodes.md) — containerd, kubelet, kube-proxy
9. [Configuring kubectl](docs/09-configuring-kubectl.md) — remote admin access
10. [Pod Network Routes](docs/10-pod-network-routes.md) — static routing between node CIDRs
11. [DNS Cluster Add-on](docs/11-dns-cluster-addon.md) — CoreDNS
12. [Smoke Test](docs/12-smoke-test.md) — prove it all works
13. [Migrating to Cilium](docs/13-migrating-to-cilium.md) — optional, swaps
    the hand-rolled CNI/kube-proxy setup for Cilium + Hubble
14. [High Availability Deep Dive](docs/14-ha-deep-dive.md) — explore why the
    cluster survives what it survives, and where that stops
15. [Disaster Recovery](docs/15-disaster-recovery.md) — etcd
    snapshot/restore, quorum loss with real data loss, rebuilding a master
    from nothing (builds on 14)
16. [Cleanup](docs/16-cleanup.md) — tear down / reset, once you're actually
    done exploring

Work through 1–12 in order — later steps assume files and state from earlier
ones. Run each command block on the node(s) named in its heading. 14 and 15
are optional post-bring-up exploration modules; 16 is the true last step —
don't run it until you're done with 14/15, since it throws away the exact
cluster those modules are built to keep breaking and un-breaking.
