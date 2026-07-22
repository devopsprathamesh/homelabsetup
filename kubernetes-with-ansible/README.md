# Kubernetes via Kubespray + Ansible — this lab

A production-pattern Kubernetes install using [Kubespray](https://github.com/kubernetes-sigs/kubespray)
(the SIG Cluster Lifecycle Ansible playbooks) against the same 7 VMs
provisioned by [`../vagrant/`](../vagrant/) — the alternative path to
[`../kubernetes-hardway/`](../kubernetes-hardway/), which builds the same
cluster by hand instead.

## Topology

| Node    | Role                              | IP            | vCPU | RAM  |
|---------|-----------------------------------|---------------|------|------|
| server  | HAProxy LB + Ansible control node | 192.168.56.10 | 1    | 1GB  |
| master1 | `etcd` + `kube_control_plane`     | 192.168.56.11 | 2    | 2GB  |
| master2 | `etcd` + `kube_control_plane`     | 192.168.56.12 | 2    | 2GB  |
| master3 | `etcd` + `kube_control_plane`     | 192.168.56.16 | 2    | 2GB  |
| node1   | `kube_node`                       | 192.168.56.13 | 1    | 2GB  |
| node2   | `kube_node`                       | 192.168.56.14 | 1    | 2GB  |
| node3   | `kube_node`                       | 192.168.56.15 | 1    | 2GB  |

All nodes: Ubuntu 24.04, `admin` user, passwordless sudo, passwordless SSH
from `server` and from the desktop host (see [../README.md](../README.md)).
Network: `192.168.56.0/24`, host-only, not reachable outside the host.

```
                              ┌─────────────────────┐
                              │   server (LB)        │
                              │   HAProxy :6443       │──── Ansible runs from here
                              └──────────┬───────────┘
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
          ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
          │ master1           │ │ master2           │ │ master3           │
          │ etcd               │◄►│ etcd              │◄►│ etcd              │
          │ kube_control_plane │ │ kube_control_plane │ │ kube_control_plane │
          └──────────────────┘ └──────────────────┘ └──────────────────┘
                    ▲                  ▲                  ▲
        ┌───────────┴──────────┬───────┴───────┬──────────┴───────────┐
        ▼                      ▼                ▼
   ┌─────────┐           ┌─────────┐      ┌─────────┐
   │ node1    │           │ node2    │      │ node3    │
   │ kube_node │           │ kube_node │      │ kube_node │
   └─────────┘           └─────────┘      └─────────┘
```

Unlike `kubernetes-hardway`, nothing here is hand-built: Kubespray's
playbooks install containerd, etcd, the control plane, kubelet/kube-proxy,
and the CNI, then wire them together — the work in this guide is choosing
correct inventory/variables and validating the result, not writing units by
hand.

## Versions used in this guide

Pin these; every command assumes them. Bump deliberately, not mid-guide —
Kubespray version and Kubernetes version are coupled, so jumping either
independently is unsupported.

| Component   | Version  |
|--------------|---------|
| Kubespray    | v2.31.0 |
| Kubernetes   | v1.35.4 (Kubespray v2.31.0 default) |
| Container runtime | containerd (Kubespray default) |
| CNI          | Calico (latest pinned by Kubespray v2.31.0) |
| Ansible (control node, in venv) | 11.13.0 (pulls in ansible-core ~2.18) |
| Python (control node)  | 3.12 (already on `server`) |

Confirmed against this exact lab on 2026-07-17: `server` reachable, all 6
cluster nodes `ping`-able over Ansible, Ubuntu 24.04.4 LTS, Python 3.12.3,
`python3-venv` and `git` available, outbound internet from `server`
(needed to clone Kubespray and pip/apt-install packages).

## Guide order

1. [Prerequisites](docs/01-prerequisites.md) — confirm the lab is in the expected state
2. [Control Node Setup](docs/02-control-node-setup.md) — venv, Kubespray clone, pinned requirements
3. [Inventory & Topology](docs/03-inventory-and-topology.md) — `etcd` / `kube_control_plane` / `kube_node` groups
4. [Cluster Configuration](docs/04-cluster-configuration.md) — `group_vars`: runtime, CIDRs, Calico
5. [Load Balancer](docs/05-load-balancer-haproxy.md) — HAProxy on `server`, API server HA
6. [Preflight Checks](docs/06-preflight-checks.md) — connectivity, syntax, resource sanity
7. [Running the Playbook](docs/07-running-the-playbook.md) — `cluster.yml`
8. [Verifying the Cluster](docs/08-verifying-the-cluster.md) — kubeconfig, smoke test
9. [Scaling Nodes](docs/09-scaling-nodes.md) — add/remove workers and masters
10. [Upgrading the Cluster](docs/10-upgrading-the-cluster.md) — `upgrade-cluster.yml`
11. [Security Hardening](docs/11-security-hardening.md) — what "production-grade" still requires beyond defaults
12. [Troubleshooting](docs/12-troubleshooting.md) — common failure modes and how to read them
13. [HA Deep Dive](docs/13-ha-deep-dive.md) — triggering and recovering from real failures, one mechanism at a time
14. [Disaster Recovery](docs/14-disaster-recovery.md) — etcd snapshot/restore, rebuilding a lost master
15. [Cleanup & Teardown](docs/15-cleanup-and-teardown.md) — `reset.yml` vs. `vagrant destroy`

Work through them in order — later steps assume state from earlier ones.
Every command is written to run from `server` (192.168.56.10) as the
Ansible control node, as `admin`, unless a step says otherwise.
