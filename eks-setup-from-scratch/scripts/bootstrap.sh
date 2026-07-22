#!/usr/bin/env bash
# First-time bootstrap: creates the S3 state backends, then applies the staging stack.
# Run from the repo root. Requires: terraform >= 1.11, aws CLI configured with an
# account that has permission to create all of this. This provisions real, billable
# AWS resources — read terraform/live/us-east-1/staging/*.tf before running `apply` for real.
set -euo pipefail

REGION="${1:-us-east-1}"

echo "==> Bootstrapping Terraform state backend in ${REGION}"
pushd "$(dirname "$0")/../terraform/modules/state-backend-bootstrap" >/dev/null
terraform init
terraform apply -var="region=${REGION}"
BUCKET=$(terraform output -raw bucket_name)
popd >/dev/null

echo "==> State bucket created: ${BUCKET}"
echo "==> Update the 'bucket' field in terraform/live/${REGION}/*/versions.tf to: ${BUCKET}"
echo "==> Then: cd terraform/live/${REGION}/staging && cp terraform.tfvars.example terraform.tfvars"
echo "    (edit it with your real values) && terraform init && terraform plan"
