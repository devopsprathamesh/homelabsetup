# Ingress & DNS: the full client-to-pod request path

This is the diagram to read if you want to understand, end to end, what happens between a user typing `https://app.example.com` and a pod actually handling the request — from an architect's point of view, every hop, every component that owns it, and which Terraform module or Kubernetes manifest is responsible.

## Component ownership

| Hop | Component | Managed by |
|---|---|---|
| Public DNS | Route53 hosted zone | Existing zone, referenced (not created) by [`terraform/live/global`](../../terraform/live/global) |
| DNS record → NLB | `external-dns` (writes records from Kubernetes `Service`/`Gateway` annotations) | [`terraform/modules/platform-addons`](../../terraform/modules/platform-addons) |
| Load balancer | Istio ingress gateway's NLB (`type: LoadBalancer`, provisioned by the AWS Load Balancer Controller) | [`terraform/modules/istio`](../../terraform/modules/istio) |
| TLS termination | Istio ingress gateway (cert from cert-manager) | [`kubernetes/istio/gateway.yaml`](../../kubernetes/istio/gateway.yaml), [`cluster-issuer.yaml`](../../kubernetes/istio/cluster-issuer.yaml) |
| Routing decision | Istio `VirtualService` | [`kubernetes/apps/workloads/example-app/base/virtualservice.yaml`](../../kubernetes/apps/workloads/example-app/base/virtualservice.yaml) |
| mTLS to the pod | Envoy sidecar ↔ Envoy sidecar | Istio control plane, mesh-wide `STRICT` `PeerAuthentication` |
| Application logic | Your container | ArgoCD-managed `Rollout` |

## End-to-end sequence

```mermaid
sequenceDiagram
    participant Browser
    participant PublicDNS as Public DNS resolver
    participant R53 as Route53
    participant NLB as Istio ingress gateway NLB
    participant IGW as Envoy (ingress gateway pod)
    participant VS as VirtualService rules\n(in-memory, pushed by istiod)
    participant SidecarStable as Envoy sidecar\n(example-app-stable pod)
    participant SidecarCanary as Envoy sidecar\n(example-app-canary pod)
    participant App as example-app container

    Browser->>PublicDNS: resolve app.example.com
    PublicDNS->>R53: recursive query (Route53 is authoritative)
    R53-->>PublicDNS: A/ALIAS record → NLB DNS name
    PublicDNS-->>Browser: resolved IP
    Browser->>NLB: TCP + TLS ClientHello (port 443)
    NLB->>IGW: forward (NLB is L4 — passes TLS through to the pod)
    IGW->>IGW: TLS terminate using cert-manager-issued\ncert (wildcard-example-com-tls secret)
    IGW->>VS: match Host: app.example.com against Gateway + VirtualService
    VS-->>IGW: route decision: 90% stable / 10% canary\n(weights set by Argo Rollouts mid-deployment)
    alt routed to stable
        IGW->>SidecarStable: mTLS request (Envoy-to-Envoy,\nmutual cert auth via istiod-issued certs)
        SidecarStable->>App: plaintext localhost call
        App-->>SidecarStable: response
        SidecarStable-->>IGW: mTLS response
    else routed to canary
        IGW->>SidecarCanary: mTLS request
        SidecarCanary->>App: plaintext localhost call
        App-->>SidecarCanary: response
        SidecarCanary-->>IGW: mTLS response
    end
    IGW-->>NLB: TLS response
    NLB-->>Browser: response
```

## Key things this diagram makes explicit

1. **The NLB is L4, not L7** — it passes TLS straight through; the Istio ingress gateway pod (Envoy) is what actually terminates TLS and makes routing decisions. This is why the NLB's target type is `ip` (pointing directly at gateway pod IPs), not `instance`.
2. **Routing weight is a live, mutable value** — during a canary rollout, the `VirtualService`'s route weights are being actively rewritten by the Argo Rollouts controller, not by a human or by ArgoCD. See [08 — Canary & Blue-Green](08-progressive-delivery-canary-bluegreen.md).
3. **Every hop past the ingress gateway is mTLS** — the browser's TLS session ends at the gateway; everything from there to the pod is a *separate*, mesh-internal mTLS session, invisible to and independent of the client's original TLS handshake.
4. **DNS resolution happens once, outside the cluster entirely** — nothing about which pod serves the request is decided by DNS; DNS only ever resolves to "the load balancer for this region."

## Cross-region behavior (DR)

The DNS step above (`R53 -->> PublicDNS`) is exactly what changes during a regional failover — the record `app.example.com` points at either the primary or DR region's NLB depending on the `terraform/modules/route53-failover` health-check state. See [../dr-ha/02-multi-region-active-passive-dr.md](../dr-ha/02-multi-region-active-passive-dr.md) and [../runbooks/dr-failover-runbook.md](../runbooks/dr-failover-runbook.md) for exactly how and when that flip happens.
