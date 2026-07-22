# Networking & VPC

Built by [`terraform/modules/vpc`](../../terraform/modules/vpc), one invocation per environment (`terraform/live/<region>/<env>`). Three tiers per AZ, three AZs minimum (enforced by a variable validation block) — this is what makes single-region HA possible at all; see [../dr-ha/01-single-region-multi-az-ha.md](../dr-ha/01-single-region-multi-az-ha.md).

## Subnet layout

```mermaid
flowchart TB
    subgraph VPC["VPC — e.g. 10.20.0.0/16 (prod)"]
        subgraph AZa["AZ us-east-1a"]
            Pa["Public /20\nALB/NLB, NAT GW"]
            Pra["Private /20\nworker nodes, pods"]
            Ia["Intra /20\nEKS control-plane ENIs\n(no route to internet)"]
        end
        subgraph AZb["AZ us-east-1b"]
            Pb["Public /20"]
            Prb["Private /20"]
            Ib["Intra /20"]
        end
        subgraph AZc["AZ us-east-1c"]
            Pc["Public /20"]
            Prc["Private /20"]
            Ic["Intra /20"]
        end
        IGW["Internet Gateway"]
        NATa["NAT GW (a)"]
        NATb["NAT GW (b)"]
        NATc["NAT GW (c)"]
    end

    Internet(("Internet")) <--> IGW
    IGW <--> Pa & Pb & Pc
    Pa --- NATa
    Pb --- NATb
    Pc --- NATc
    Pra -->|egress| NATa
    Prb -->|egress| NATb
    Prc -->|egress| NATc
```

Prod and DR-prod get **one NAT gateway per AZ** (`single_nat_gateway = false`) — a single NAT/AZ failure can't take out egress for the other two AZs. Staging uses one shared NAT gateway to cut cost, since it isn't held to the same availability bar.

## Subnet purpose and tagging

| Tier | Purpose | Key tags |
|---|---|---|
| Public | ALB/NLB placement, NAT gateways | `kubernetes.io/role/elb=1`, `kubernetes.io/cluster/<name>=shared` |
| Private | Worker nodes, pod ENIs | `kubernetes.io/role/internal-elb=1`, `karpenter.sh/discovery=<cluster>` |
| Intra | EKS control-plane cross-account ENIs only — no route to 0.0.0.0/0 in either direction | none (not used for workload placement) |

The `karpenter.sh/discovery` tag on private subnets is what Karpenter's default `EC2NodeClass` (`terraform/modules/eks-karpenter/main.tf`) uses for `subnetSelectorTerms` — no hardcoded subnet IDs anywhere in the Karpenter config.

## VPC Flow Logs

Enabled by default (`enable_flow_log = true`) to CloudWatch — the first thing you want available during a network-layer incident, and cheap enough to leave on permanently.

## DNS resolution flow (in-cluster)

How a pod resolves another Kubernetes Service name (e.g. `example-app-stable.example-app.svc.cluster.local`):

```mermaid
sequenceDiagram
    participant Pod
    participant Kubelet as Node kubelet\n(/etc/resolv.conf → ClusterIP of kube-dns)
    participant CoreDNS as CoreDNS pods\n(spread across AZs)
    participant K8sAPI as kube-apiserver\n(Service/Endpoints watch)
    participant VPCResolver as Amazon-provided\nVPC DNS Resolver (.2)

    Pod->>Kubelet: DNS query: example-app-stable.example-app.svc.cluster.local
    Kubelet->>CoreDNS: forwarded to kube-dns ClusterIP
    CoreDNS->>K8sAPI: (cached) Service → ClusterIP mapping
    CoreDNS-->>Pod: A record: Service ClusterIP
    Note over Pod,CoreDNS: For non-cluster.local names (e.g. an external API),<br/>CoreDNS forwards upstream instead:
    Pod->>Kubelet: DNS query: api.stripe.com
    Kubelet->>CoreDNS: forwarded
    CoreDNS->>VPCResolver: forward (CoreDNS's default upstream)
    VPCResolver-->>CoreDNS: public DNS answer
    CoreDNS-->>Pod: A record
```

CoreDNS runs on the tainted "core" node group with a `topologySpreadConstraint` across `topology.kubernetes.io/zone` ([`terraform/modules/eks-core-addons/main.tf`](../../terraform/modules/eks-core-addons/main.tf)) — losing one AZ never takes cluster DNS down with it.

## External (client-facing) DNS resolution

Covered end-to-end, with the full request path past DNS resolution, in [07 — Ingress & DNS](07-ingress-dns.md).
