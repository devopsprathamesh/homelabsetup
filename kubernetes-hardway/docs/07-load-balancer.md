# 07 — Load Balancer

Run on **`server`** (`ssh admin@lab-server`).

The API server terminates its own TLS and does client-cert auth, so the LB
must do plain **TCP passthrough** on 6443 — not TLS termination, which
would break client-cert auth for everything behind it (kubelet, kube-proxy,
kubectl all present their own client certs directly to the apiserver).
HAProxy in `mode tcp` does exactly this.

## 1. Install HAProxy

```bash
sudo apt update
sudo apt install -y haproxy
haproxy -v
```

## 2. Configure

```bash
cat <<'EOF' | sudo tee /etc/haproxy/haproxy.cfg
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

frontend kubernetes-api
    bind *:6443
    default_backend kubernetes-masters

backend kubernetes-masters
    balance roundrobin
    option tcp-check
    server master1 192.168.56.11:6443 check
    server master2 192.168.56.12:6443 check
    server master3 192.168.56.16:6443 check

listen stats
    bind *:9000
    mode http
    stats enable
    stats uri /
    stats refresh 10s
EOF
```

`option tcp-check` makes HAProxy open (and immediately close) a TCP
connection to each backend to decide if it's up — good enough here since a
closed apiserver port is the dominant failure mode in this lab. The `stats`
listener on `:9000` is optional but useful for watching failover live —
reachable at `http://192.168.56.10:9000/` (host-only network only).

## 3. Validate and restart

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
sudo systemctl enable haproxy
sudo systemctl status haproxy --no-pager
```

## 4. Verify

From `server` itself:

```bash
curl -k https://127.0.0.1:6443/version
```

You should get a Kubernetes version JSON response (a `401 Unauthorized`
body is also fine here — that's the apiserver correctly rejecting an
unauthenticated `curl`, and proves TCP passthrough is reaching it. A
connection *refused* or *timeout* means HAProxy or a master's apiserver is
down).

Watch it survive a master going away:

```bash
# on master1
sudo systemctl stop kube-apiserver
# from server
watch -n1 'curl -sk -o /dev/null -w "%{http_code}\n" https://127.0.0.1:6443/version'
# on master1, restore it
sudo systemctl start kube-apiserver
```

The stats page (`:9000/`) should show `master1` flip to red and traffic
shift entirely to `master2` within a couple of health-check intervals.

Next: [08 — Bootstrapping Worker Nodes](08-bootstrapping-worker-nodes.md)
