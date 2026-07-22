#!/usr/bin/env bash
# Thin wrapper around the manual steps in docs/runbooks/dr-failover-runbook.md.
# This does NOT fully automate failover — it's a checklist-runner, not a one-button
# failover, because a real regional failover deserves a human decision at each step.
# Read the runbook before running this.
set -euo pipefail

echo "This script walks the DR failover runbook step by step."
echo "Full detail: docs/runbooks/dr-failover-runbook.md"
echo

read -r -p "Have you confirmed this is a real regional outage (not an AZ issue or bad deploy)? [y/N] " confirmed
[[ "$confirmed" == "y" ]] || { echo "Aborting — see docs/runbooks/dr-failover-runbook.md step 0."; exit 1; }

echo "==> Pointing kubectl at the DR cluster (us-west-2)"
aws eks update-kubeconfig --name eks-platform-dr-prod --region us-west-2

echo "==> Recent Velero backups:"
velero backup get

read -r -p "Restore from the most recent backup now? [y/N] " do_restore
if [[ "$do_restore" == "y" ]]; then
  read -r -p "Backup name to restore: " backup_name
  velero restore create --from-backup "$backup_name"
  velero restore describe --details "$(velero restore get -o name | tail -1)"
fi

read -r -p "Scale example-app to production replica count now? [y/N] " do_scale
if [[ "$do_scale" == "y" ]]; then
  kubectl argo rollouts scale example-app --replicas=6 -n example-app
fi

echo "==> Checking DNS resolution for app.example.com"
dig +short app.example.com

echo "==> Done with the automatable steps. Continue with runbook steps 4-6 manually:"
echo "    smoke test, monitoring, stakeholder communication, and eventual failback."
