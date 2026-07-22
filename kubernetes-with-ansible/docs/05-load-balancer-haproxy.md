# 05 — Load Balancer (HAProxy on `server`)

`server` is already labeled "load balancer / entry point" in this repo's
topology — this doc is what makes that real for the Kubernetes API server.
Do this **before** [07 — Running the Playbook](07-running-the-playbook.md):
the LB address from doc 04 gets baked into every cert and kubeconfig at
bootstrap time.

## 1. Install HAProxy on `server`

```bash
ssh admin@lab-server
sudo apt-get update
sudo apt-get install -y haproxy
```

## 2. Configure it to front the three masters' apiservers

Write `/etc/haproxy/haproxy.cfg` (back up the original first:
`sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.orig`):

```
global
    log /dev/log local0
    maxconn 4096

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend k8s_apiserver
    bind *:6443
    mode tcp
    option tcplog
    default_backend k8s_apiserver_backend

backend k8s_apiserver_backend
    mode tcp
    option tcp-check
    balance roundrobin
    default-server inter 5s fall 2 rise 2
    server master1 192.168.56.11:6443 check
    server master2 192.168.56.12:6443 check
    server master3 192.168.56.16:6443 check
```

`mode tcp` (not `http`) is required — the apiserver terminates its own TLS,
so HAProxy just needs to pass bytes through, not inspect them.

## 3. Enable and start it

```bash
sudo systemctl enable haproxy
sudo systemctl restart haproxy
sudo systemctl status haproxy --no-pager
```

## 4. Verify it's listening (before there's anything behind it yet)

```bash
sudo ss -tlnp | grep 6443
```

You'll see connection resets/timeouts to the masters until Kubespray
actually installs an apiserver on them — that's expected at this stage.
Re-check after doc 07:

```bash
curl -sk https://192.168.56.10:6443/version
```

Once the cluster is up, this should return the Kubernetes version JSON
without a certificate error (Calico/cluster is up and the LB address is a
valid cert SAN because of doc 04's `supplementary_addresses_in_ssl_keys`).

## Known limitation: `server` is a single point of failure

This gives you HA **masters** (survive losing 1 of 3), but the LB itself
isn't HA — if `server` goes down, nothing can reach the apiserver even
though `master1-3` are fine. Genuinely removing that SPOF needs either:

- A second LB node + `keepalived` sharing a floating VIP (the classic
  HAProxy+keepalived pattern) — needs one more VM.
- `kube-vip` running as a static pod on the masters themselves instead of
  an external LB — no extra VM, but different failure characteristics
  (ARP-based VIP failover between masters).

Out of scope for this lab's VM budget; noted again in
[11 — Security Hardening](11-security-hardening.md) as a real
production gap, not just a lab shortcut, and demonstrated hands-on in
[13 — HA Deep Dive](13-ha-deep-dive.md) §7.

Next: [06 — Preflight Checks](06-preflight-checks.md)
