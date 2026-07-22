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

Guard `encryption-config.yaml` like a secret — anyone with this file can
decrypt every Secret stored in etcd. It isn't committed to this repo;
regenerate it if you ever suspect it leaked (requires re-encrypting
existing Secrets, see the Kubernetes docs on encryption-at-rest key
rotation).

Next: [05 — Bootstrapping etcd](05-bootstrapping-etcd.md)
