# Canary & Blue-Green Deployments

Both strategies are implemented with **Argo Rollouts**, which replaces `Deployment` with a `Rollout` custom resource of the same shape plus a `strategy` block. Traffic shifting is delegated to Istio (`VirtualService` weights for canary; two `Service` selectors for blue-green) — Argo Rollouts never touches pods' network paths directly, it only mutates Istio/Service objects and lets the mesh do the actual routing.

## Canary (this platform's default — [`kubernetes/apps/workloads/example-app/base/rollout.yaml`](../../kubernetes/apps/workloads/example-app/base/rollout.yaml))

Traffic shifts gradually, with automated analysis gates between steps. A failed gate rolls back automatically — no human has to notice and react.

```mermaid
flowchart LR
    subgraph Step0["Start: 100% / 0%"]
        S0S["stable"] -.100%.-> Traffic0(("traffic"))
        S0C["canary (new version)"] -.0%.-> Traffic0
    end
    subgraph Step1["setWeight: 10, pause 2m, then analyze"]
        S1S["stable"] -.90%.-> Traffic1(("traffic"))
        S1C["canary"] -.10%.-> Traffic1
    end
    subgraph Step2["setWeight: 30, pause 5m"]
        S2S["stable"] -.70%.-> Traffic2(("traffic"))
        S2C["canary"] -.30%.-> Traffic2
    end
    subgraph Step3["setWeight: 60, pause 5m"]
        S3S["stable"] -.40%.-> Traffic3(("traffic"))
        S3C["canary"] -.60%.-> Traffic3
    end
    subgraph Step4["setWeight: 100 — promoted"]
        S4C["canary becomes\nnew stable"] -.100%.-> Traffic4(("traffic"))
    end
    Step0 --> Step1 --> Step2 --> Step3 --> Step4

    Analysis{{"AnalysisTemplate:\nsuccess-rate >= 95%\n(queries in-cluster Prometheus)"}}
    Step1 -.gate.-> Analysis
    Analysis -->|pass| Step2
    Analysis -->|"fail (3x)"| Rollback["Automatic rollback:\nweight → 100/0, canary scaled down"]
```

**When to use it**: continuous, low-risk exposure of a new version to a growing traffic slice, with metrics-driven automated gating. Best for services with reliable success-rate/latency signals and enough traffic volume that a 10% slice is statistically meaningful.

## Blue-Green ([`kubernetes/apps/workloads/example-app/rollout-bluegreen-example.yaml`](../../kubernetes/apps/workloads/example-app/rollout-bluegreen-example.yaml) — illustrative, swap in for the canary strategy)

The new version ("green"/preview) runs at full scale *before* it receives any production traffic, reachable only via its own preview `Service` for smoke testing. Promotion is an instant, all-at-once cutover — not a gradual shift.

```mermaid
flowchart TB
    subgraph Before["Before promotion"]
        Active1["activeService\n(example-app-stable)\n→ v1 pods (blue)"] -.100% prod traffic.-> ProdTraffic1(("production traffic"))
        Preview1["previewService\n(example-app-canary)\n→ v2 pods (green)"] -.smoke-test traffic only.-> Tester(("QA / automated smoke test"))
    end
    Before -->|"prePromotionAnalysis passes\n+ manual or automated promote"| Promote{{"Promotion:\nswap Service selectors"}}
    Promote --> After
    subgraph After["After promotion"]
        Active2["activeService\n→ v2 pods (green)"] -.100% prod traffic.-> ProdTraffic2(("production traffic"))
        Old["v1 pods (blue)\nkept alive scaleDownDelaySeconds: 300"] -.idle, instant rollback target.-> Nothing[" "]
    end
```

**When to use it**: changes too risky or too structurally different to canary safely (schema migrations paired with app changes, anything where serving two versions simultaneously to real users is unacceptable), or where you want a guaranteed-instant, single-command rollback rather than a weight ramp-down. Costs 2x replica capacity for the `scaleDownDelaySeconds` window.

## Rollback

Both strategies support the same rollback primitive — `kubectl argo rollouts undo <name>` (or ArgoCD's own rollback UI, since it's a Git-tracked spec change). Canary auto-rollback via failed `AnalysisTemplate` runs is the default expectation; blue-green rollback is manual/instant since the old ReplicaSet is still warm. See [../runbooks/canary-rollback-runbook.md](../runbooks/canary-rollback-runbook.md) for the exact commands and what to check first.
