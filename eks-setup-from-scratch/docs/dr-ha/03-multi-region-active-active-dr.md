# HA Tier 3: Multi-Region Active-Active

**Status: documented extension pattern, not a separately built Terraform stack.** This tier reuses everything from [Tier 2](02-multi-region-active-passive-dr.md) — same two regions, same modules — with two changes: both clusters run at full production scale continuously, and Route53 switches from failover routing to latency-based routing. It is *not* a third `terraform/live/` stack; it's a different configuration of the same two.

## Why this isn't fully built here

Active-active's hard part is never the Kubernetes/compute layer — Karpenter, Istio, and ArgoCD are already symmetric across both regions in Tier 2. The hard part is the **data layer**, which this repo deliberately doesn't include (no RDS, no ElastiCache, no app-specific datastore). Going active-active for real requires a concrete answer to "what happens when the same record is written in both regions near-simultaneously," and that answer is entirely dependent on what data store you actually use:

| Data layer choice | Active-active strategy |
|---|---|
| DynamoDB Global Tables | Native multi-region, last-writer-wins conflict resolution — closest to "just works" |
| Aurora Global Database | One writer region, read replicas in the other — this is actually active-**read**-active-write, not full active-active |
| Self-managed Postgres/MySQL | Requires an explicit conflict-resolution strategy (e.g. CRDTs, application-level partitioning by user/tenant) — genuinely hard, often the wrong investment vs. Tier 2 |
| Stateless / cache-only workloads | Trivially active-active — no conflict possible | 

**Recommendation**: don't reach for this tier until a concrete data-layer decision exists. Tier 2 already gets you a sub-minutes RTO; the marginal benefit of Tier 3 (near-zero RTO, no DNS propagation wait) rarely justifies the data-layer complexity unless you have a hard multi-region-write requirement.

## What changes from Tier 2

```mermaid
flowchart TB
    subgraph UsEast1["us-east-1 (ACTIVE)"]
        EKS1["EKS cluster: prod\nfull replica count,\nfull Karpenter capacity"]
        NLB1["Istio ingress NLB"]
    end
    subgraph UsWest2["us-west-2 (ACTIVE)"]
        EKS2["EKS cluster: dr-prod → rename to prod-west\nfull replica count,\nfull Karpenter capacity"]
        NLB2["Istio ingress NLB"]
    end
    subgraph Global["terraform/live/global"]
        R53["Route53 LATENCY routing\n(terraform/modules/route53-failover, mode=\"latency\")\napp.example.com"]
        HC1["Health check: us-east-1"]
        HC2["Health check: us-west-2"]
    end

    ClientA(("Client — US East")) --> R53
    ClientB(("Client — Europe/West")) --> R53
    R53 -->|lowest latency| NLB1 --> EKS1
    R53 -->|lowest latency| NLB2 --> EKS2
    HC1 -.-> NLB1
    HC2 -.-> NLB2
```

1. **`terraform/modules/route53-failover`** already supports this — set `mode = "latency"` instead of `"failover"` when invoking it from `terraform/live/global`. It creates per-region `latency_routing_policy` records with health checks on both, instead of PRIMARY/SECONDARY.
2. **Both clusters run prod-equivalent sizing** — in Tier 2, `dr-prod`'s `core_node_desired_size` and app replica counts are intentionally low (warm standby). For Tier 3, size `dr-prod` identically to `prod` (same `core_node_*` values, same `Rollout` replica counts in `kubernetes/apps/workloads/example-app/overlays/dr-prod`).
3. **Velero's role shrinks or disappears** — it stops being the DR data-recovery mechanism (both regions are already live) and becomes purely a backup-for-accidental-deletion tool, same as it would be in a single-region deployment.
4. **ArgoCD in both clusters already syncs the same repo continuously** — no change needed here; this was already true in Tier 2, since the DR cluster's ArgoCD was always live.

## Traffic flow difference from Tier 2

The only architectural difference from the [07 — Ingress & DNS](../architecture/07-ingress-dns.md) request flow is the **first hop**: instead of "Route53 always answers with the primary region unless its health check is failing," Route53 answers with **whichever region has lower measured latency to the resolver making the query** — so two users in different geographies can be served by two different regions simultaneously, both serving live production traffic, both able to accept writes if your data layer supports it.

## When to actually build this

Build it as a **deliberate, separate change** once: (a) you have a concrete multi-region-write-capable data layer decision, and (b) you've measured that Tier 2's RTO genuinely doesn't meet your SLA. At that point, the Terraform change itself is small (resize `dr-prod`, flip the `route53-failover` module's `mode` variable) — the real work is entirely in the data layer, which is outside this repo's scope.
