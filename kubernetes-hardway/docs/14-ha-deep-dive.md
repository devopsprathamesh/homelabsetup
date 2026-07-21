# 14 — High Availability Deep Dive

[12 — Smoke Test](12-smoke-test.md) §8 proved the cluster *survives* losing
a master. This doc is about understanding *why*, and where that protection
actually ends — three separate HA mechanisms are stacked in this cluster,
each with a different failure boundary, and it's worth seeing each one
individually before you can reason about it.

Run everything below from your **client machine**, using the kubeconfig
from [09](09-configuring-kubectl.md), unless a step says otherwise. Nothing
here is destructive in a way that loses data — every scenario restarts what
it stopped — but do these one at a time, not layered on each other, so you
can tell which mechanism you're actually observing.

Prerequisite: a healthy cluster that's passed the smoke test, so a failure
you cause is the only variable.

## The three HA mechanisms, and their limits

| Mechanism | What it protects | Survives | Does NOT survive |
|---|---|---|---|
| HAProxy round-robin (07) | Reaching *some* apiserver | 1 of 3 masters unreachable | `server` itself dying — it's a single node, not HA |
| etcd Raft quorum (05) | Cluster state (the source of truth) | losing any 1 of 3 members | losing 2 of 3 (quorum lost — this is where DR starts, see below) |
| Leader election (06) | Exactly one active controller-manager/scheduler | the leader dying — a new one takes over in seconds | nothing controller-manager/scheduler-specific; they're stateless, the lease just moves |

Keep this table in mind through the rest of the doc — each section below
maps to one row.

## 1. Baseline: who's actually in charge right now

All 3 masters run their own `kube-controller-manager` and `kube-scheduler`,
but only one of each is *active* — the rest are idle standbys blocked on a
lease. See which:

```bash
kubectl -n kube-system get lease kube-scheduler kube-controller-manager -o \
  custom-columns=NAME:.metadata.name,HOLDER:.spec.holderIdentity,RENEWED:.spec.renewTime
```

The `HOLDER` column names a specific master (with a random suffix) — that's
the leader for each. It's entirely possible `kube-scheduler`'s leader is on
`master2` while `kube-controller-manager`'s is on `master3` — leadership is
independent per component, not per node.

## 2. apiserver loss on the leader-holding master (repeat of 12§8, watched live)

Open two terminals. In one, watch the LB flip:

```bash
watch -n1 'curl -sk -o /dev/null -w "%{http_code}\n" https://192.168.56.10:6443/version'
```

In the other, stop the apiserver on whichever master §1 showed holding a
lease:

```bash
ssh admin@lab-master1 'sudo systemctl stop kube-apiserver'   # substitute the actual leader host
kubectl get nodes    # still works — HAProxy just stopped routing to master1
ssh admin@lab-master1 'sudo systemctl start kube-apiserver'
```

This exercises row 1 of the table — the LB, not etcd or leader election.
`kube-controller-manager`/`kube-scheduler` on `master1` also lost their
apiserver connection during this window; if `master1` held either lease,
expect a leader handover (see §4) as a side effect.

## 3. Simulating a full node crash, not just one process

§2 only stopped `kube-apiserver`. A real crash takes etcd,
controller-manager, and scheduler down too — closer to what actually
happens when a VM dies:

```bash
ssh admin@lab-master1 'sudo systemctl stop kube-apiserver kube-controller-manager kube-scheduler etcd'
kubectl get nodes                       # still fine — 2 masters, 2/3 etcd quorum
kubectl create deployment ha-check --image=nginx --replicas=1
kubectl rollout status deployment/ha-check
ssh admin@lab-master1 'sudo systemctl start etcd kube-apiserver kube-controller-manager kube-scheduler'
```

`kubectl create deployment` succeeding here matters more than `get nodes`
does — `get` is a read, `create` is a write that has to go through etcd
consensus. Confirm `master1` rejoins etcd cleanly:

```bash
ssh admin@lab-master1 'sudo ETCDCTL_API=3 etcdctl endpoint health --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem'
kubectl delete deployment ha-check
```

## 4. Watching leader election actually happen

§1 told you who the leader is; this section makes it move and proves the
cluster kept scheduling through the handover — not just that a new leader
eventually got picked.

```bash
LEADER=$(kubectl -n kube-system get lease kube-scheduler -o jsonpath='{.spec.holderIdentity}' | sed -E 's/_.*//')
echo "kube-scheduler leader is on: ${LEADER}"

ssh admin@lab-${LEADER} 'sudo systemctl stop kube-scheduler'
kubectl create deployment leader-check --image=nginx --replicas=1
kubectl rollout status deployment/leader-check --timeout=30s
kubectl -n kube-system get lease kube-scheduler -o jsonpath='{.spec.holderIdentity}'; echo
ssh admin@lab-${LEADER} 'sudo systemctl start kube-scheduler'
kubectl delete deployment leader-check
```

Default lease duration is 15s, so `rollout status` succeeding within the
30s timeout is the proof — if failover were broken, the Pod would sit
`Pending` (no scheduler assigning it a node) until the stopped scheduler
came back.

## 5. The etcd quorum boundary — where HA stops and DR starts

Everything above tolerated losing **one** master. This section
deliberately crosses that line, on purpose, so you can see the difference
between *degraded* and *down* — and importantly, that not all "down" is
data loss.

```bash
ssh admin@lab-master1 'sudo systemctl stop etcd'
ssh admin@lab-master2 'sudo systemctl stop etcd'
# only master3's etcd is left — 1 of 3, no majority

kubectl get nodes    # this will hang and time out, not just fail fast
```

Notice it **hangs**, not `Ready`/`NotReady` — etcd's default reads are
linearizable, meaning even a `GET` needs quorum, so both reads and writes
stop, not just writes. The cluster isn't corrupted; it's correctly refusing
to answer without a majority, because a minority partition can't be trusted
to have the latest state.

Recover it — since the two stopped members still have their on-disk data
intact, this is a quorum recovery, not a restore:

```bash
ssh admin@lab-master1 'sudo systemctl start etcd'
ssh admin@lab-master2 'sudo systemctl start etcd'
sleep 5
kubectl get nodes    # back immediately once quorum re-forms
```

**This is the concept to carry into DR later**: what you just did works
*only* because `/var/lib/etcd` on `master1`/`master2` was never touched —
the data came back the moment the processes did. Real disaster recovery is
what you need when that data directory is gone (disk failure, `rm -rf`
gone wrong, all 3 members lost at once) — no amount of `systemctl start`
fixes that; you need a snapshot restore. That's the subject of the
disaster-recovery doc, once you've internalized this boundary.

## 6. Worker-side HA: Deployments vs. bare Pods

Control-plane HA keeps the cluster's brain alive; it says nothing about
whether your workloads survive a **worker** dying. That's a different
mechanism — the controller-manager's replica-count reconciliation — and it
only applies to controller-owned Pods, not bare ones.

```bash
kubectl create deployment worker-ha --image=nginx --replicas=1
kubectl run lonely-pod --image=nginx --restart=Never
kubectl wait --for=condition=Ready pod -l app=worker-ha --timeout=30s
kubectl wait --for=condition=Ready pod/lonely-pod --timeout=30s

DEPLOY_NODE=$(kubectl get pods -l app=worker-ha -o jsonpath='{.items[0].spec.nodeName}')
echo "worker-ha pod is on: ${DEPLOY_NODE}"

ssh admin@${DEPLOY_NODE} 'sudo systemctl stop kubelet containerd'
```

Watch what happens over the next few minutes (defaults: node marked
`NotReady` after ~40s, Pods on it evicted after a further 5m):

```bash
watch kubectl get nodes,pods -o wide
```

Expect `worker-ha`'s Pod to eventually get rescheduled onto a healthy node
(the Deployment's ReplicaSet controller notices the gap and creates a
replacement) — but `lonely-pod` just sits `Terminating`/gone with nothing
recreating it, because nothing owns it. This is why bare Pods are a smoke-
test convenience, never a real workload pattern.

Recover the node and clean up:

```bash
ssh admin@${DEPLOY_NODE} 'sudo systemctl start containerd kubelet'
kubectl delete deployment worker-ha
kubectl delete pod lonely-pod --ignore-not-found
```

## 7. The gap this lab doesn't cover: the load balancer itself

Every scenario above assumes `server` is up, because every `kubectl`
command gets there through it. `server` is a **single VM running a single
HAProxy process** — nothing in this topology makes it HA. If you stop it:

```bash
ssh admin@lab-server 'sudo systemctl stop haproxy'
kubectl get nodes   # times out — not because the control plane is down, but because you can't reach it
ssh admin@lab-server 'sudo systemctl start haproxy'
```

The masters and etcd are all still fine during this — `ssh admin@lab-master1
'curl -sk https://127.0.0.1:6443/version'` would confirm it — but nothing
external can tell, because the only door in just got locked. This is the
honest limit of this 7-VM lab: real production HA puts 2+ LB nodes behind
something like keepalived/VRRP (a floating virtual IP that moves between
them) or a cloud load balancer, so the entry point itself has no single
point of failure. Worth understanding as a concept even though building it
here would mean adding an 8th VM this lab's topology doesn't have.

## Summary

You've now individually triggered and recovered from: apiserver loss,
full-node loss, leader election handover, etcd quorum loss (and the
specific reason it's recoverable without a restore), worker-node loss with
and without a controller, and the LB's own single point of failure. That's
the complete HA picture for this lab.

Next: disaster recovery (etcd snapshot/restore, full quorum loss *with*
data loss, rebuilding a master from nothing) builds directly on §5 above —
ask when you're ready to start that module and it'll land as
`15-disaster-recovery.md`.
