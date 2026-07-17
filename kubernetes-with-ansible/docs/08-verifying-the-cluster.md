# 08 — Verifying the Cluster

## 1. Fetch the admin kubeconfig

Kubespray writes it on every `kube_control_plane` host at
`/etc/kubernetes/admin.conf`. Pull it to `server` and point it at the LB
address instead of a single master:

```bash
ssh admin@lab-server
mkdir -p ~/.kube
sudo cat /etc/kubernetes/admin.conf > ~/.kube/config
sed -i 's/127.0.0.1:6443/192.168.56.10:6443/' ~/.kube/config
chmod 600 ~/.kube/config
```

(Kubespray typically points the embedded server URL at `localhost:6443`
via that host's own kube-vip/HAProxy sidecar if configured, or at the
first master directly — the `sed` above forces it through the real LB from
doc 05 regardless, so a rebuilt kubeconfig doesn't quietly bypass it.)

## 2. Install `kubectl` on `server` if not already present

```bash
curl -L -o kubectl https://dl.k8s.io/release/v1.35.4/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

## 3. Check node status

```bash
kubectl get nodes -o wide
```

Expect all 6 (`master1-3`, `node1-3`) `Ready`, masters showing the
`control-plane` role label.

## 4. Check core system pods

```bash
kubectl get pods -n kube-system -o wide
```

Expect `Running` for: `kube-apiserver-*` ×3, `kube-controller-manager-*`,
`kube-scheduler-*`, `etcd-*` ×3, `kube-proxy-*` ×6, `coredns-*`, and the
Calico pods (`calico-node-*` ×6, `calico-kube-controllers-*`).

## 5. Cluster-info and component health

```bash
kubectl cluster-info
kubectl get componentstatuses   # deprecated API but still a quick eyeball check
```

## 6. Smoke test — deploy something and reach it

```bash
kubectl create deployment nginx-smoke --image=nginx:stable --replicas=2
kubectl expose deployment nginx-smoke --port=80 --type=ClusterIP
kubectl wait --for=condition=available --timeout=90s deployment/nginx-smoke
kubectl run curl-smoke --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://nginx-smoke
```

Expect the default nginx welcome page HTML back. Confirms: scheduling
across nodes, kube-proxy service routing, Calico pod-to-pod networking,
and image pulls all work end to end.

## 7. Clean up the smoke test

```bash
kubectl delete deployment nginx-smoke
kubectl delete service nginx-smoke
```

Next: [09 — Scaling Nodes](09-scaling-nodes.md)
