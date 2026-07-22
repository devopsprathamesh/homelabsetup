# 04 — Data Encryption Config and Key

Kubernetes can encrypt Secrets at rest in etcd. This generates the AES key
and the `EncryptionConfiguration` the API server reads on startup.

Run on the **client machine**, inside `~/k8s-the-hard-way`.

```bash
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

cat > encryption-config.yaml <<EOF
kind: EncryptionConfiguration
apiVersion: apiserver.config.k8s.io/v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
```

The `identity: {}` provider is listed second as a fallback so already-plain
data stays readable during a future re-key rotation; new writes use
`aescbc` (first provider wins for writes).

## What happens on the write path

```mermaid
sequenceDiagram
    participant C as kubectl create secret
    participant A as kube-apiserver
    participant E as etcd
    C->>A: Secret (plaintext over TLS)
    A->>A: match resource "secrets" in EncryptionConfiguration
    A->>A: encrypt value with aescbc key1<br/>(first provider = write provider)
    A->>E: store "k8s:enc:aescbc:v1:key1:&lt;ciphertext&gt;"
    Note over E: etcd only ever sees ciphertext
    E-->>A: read: ciphertext
    A->>A: prefix "k8s:enc:aescbc:v1:key1:" selects<br/>provider + key for decryption
    A-->>C: Secret (plaintext over TLS)
```

The API server is the only component that holds the key — etcd itself does
no crypto. On every write of a matched resource it encrypts with the *first*
provider; on every read it picks the provider by the `k8s:enc:...` prefix
stored with the value (bare values fall through to `identity`, which is why
listing it last keeps old plaintext data readable). This is also why the
config must be identical on all three masters: a Secret written via
`master1` must be decryptable by an apiserver on `master2`.

Use `kind: EncryptionConfiguration` / `apiVersion: apiserver.config.k8s.io/v1`
here, not the older `EncryptionConfig`/`v1` you'll see in some tutorials —
that legacy pair still decodes today only because apiserver keeps a
backward-compat alias for it, not because it's the current API.

Distribute to all three control-plane nodes, into its own `encryptionkey/`
subdirectory under `~/k8s-the-hard-way` (kept separate from `certificates/`
and `kubeconfig/` since it's neither):

```bash
for master in master1 master2 master3; do
  ssh admin@lab-${master} "mkdir -p ~/k8s-the-hard-way/encryptionkey"
  scp encryption-config.yaml admin@lab-${master}:~/k8s-the-hard-way/encryptionkey/
done
```

## Verify (after the control plane is up)

You can't test this until the API server is running (doc
[06](06-bootstrapping-control-plane.md)), but note the check now — it's the
same one used in the smoke test ([12 §1](12-smoke-test.md)). Create a Secret,
then read its raw etcd value on a master:

```bash
kubectl create secret generic hardway-enc-test --from-literal=k=v

ssh admin@lab-master1 "sudo ETCDCTL_API=3 etcdctl \
  --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem \
  get /registry/secrets/default/hardway-enc-test | hexdump -C | head"
```

Expected: the value starts with `k8s:enc:aescbc:v1:key1:` followed by
ciphertext — not the readable string `v`. If you see plaintext, the
apiserver was started without `--encryption-provider-config` (or with the
`identity` provider listed first).

Guard `encryption-config.yaml` like a secret — anyone with this file can
decrypt every Secret stored in etcd. It isn't committed to this repo;
regenerate it if you ever suspect it leaked (requires re-encrypting
existing Secrets, see the Kubernetes docs on encryption-at-rest key
rotation).

Next: [05 — Bootstrapping etcd](05-bootstrapping-etcd.md)
