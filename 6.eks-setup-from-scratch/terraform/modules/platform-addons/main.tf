# Platform-level addons via AWS's own reference module. NOTE ON IAM: this module's
# native IAM submodules default to IRSA (not Pod Identity) for these specific
# controllers as of v1.18 — unlike our hand-rolled Karpenter/EBS-CSI modules, which use
# Pod Identity directly. Running both mechanisms side by side is intentional and safe
# (they're not mutually exclusive — a cluster can have both an OIDC provider and Pod
# Identity Agent active), and is documented in docs/architecture/03-security-iam-encryption.md
# rather than papered over.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
  }
}

locals {
  # Strip "arn:aws:iam::<account>:oidc-provider/" down to the bare issuer URL for use in
  # the federated trust policy's condition keys below.
  oidc_provider_url = replace(var.oidc_provider_arn, "/^(.*provider\\/)/", "")
}

module "addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.18"

  cluster_name      = var.cluster_name
  cluster_endpoint  = var.cluster_endpoint
  cluster_version   = var.cluster_version
  oidc_provider_arn = var.oidc_provider_arn

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    set = [
      {
        name  = "enableServiceMutatorWebhook"
        value = "false"
      }
    ]
  }

  enable_external_dns = true
  external_dns = {
    values = [yamlencode({
      provider   = "aws"
      policy     = "sync"
      txtOwnerId = var.cluster_name
    })]
  }
  external_dns_route53_zone_arns = var.route53_zone_arns

  enable_cert_manager = true
  cert_manager = {
    values = [yamlencode({
      installCRDs = true
    })]
  }
  cert_manager_route53_hosted_zone_arns = var.route53_zone_arns

  # external-secrets and Fluent Bit aren't first-class flags on this module version —
  # installed via the generic helm_releases map, same IRSA pattern as everything else here.
  helm_releases = {
    external-secrets = {
      name             = "external-secrets"
      namespace        = "external-secrets"
      create_namespace = true
      repository       = "https://charts.external-secrets.io"
      chart            = "external-secrets"
      version          = var.external_secrets_chart_version
      values = [yamlencode({
        installCRDs = true
        serviceAccount = {
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn
          }
        }
      })]
    }

    fluent-bit = {
      name             = "aws-for-fluent-bit"
      namespace        = "logging"
      create_namespace = true
      repository       = "https://aws.github.io/eks-charts"
      chart            = "aws-for-fluent-bit"
      version          = var.fluent_bit_chart_version
      values = [yamlencode({
        serviceAccount = {
          create = true
          name   = "aws-for-fluent-bit"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.fluent_bit.arn
          }
        }
        cloudWatchLogs = {
          enabled          = true
          region           = var.region
          logGroupName     = "/eks/${var.cluster_name}/application"
          logGroupTemplate = ""
          logStreamPrefix  = "app-"
          autoCreateGroup  = true
        }
        tolerations = [
          { operator = "Exists" } # Fluent Bit is a DaemonSet — must run on every node, including tainted ones.
        ]
      })]
    }
  }

  tags = var.tags
}

# --- Velero: cluster resource + EBS volume snapshot backup/restore, the actual DR
# data-plane mechanism (see terraform/modules/backup-bucket and
# docs/dr-ha/02-multi-region-active-passive-dr.md). Only enabled where var.enable_velero
# is true — the primary cluster schedules backups, the DR cluster restores from them.
resource "aws_iam_role" "velero" {
  count = var.enable_velero ? 1 : 0

  name = "${var.cluster_name}-velero"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "velero" {
  count = var.enable_velero ? 1 : 0

  name = "velero-backup-restore"
  role = aws_iam_role.velero[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.velero_bucket_name}",
          "arn:aws:s3:::${var.velero_bucket_name}/*",
        ]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "velero" {
  count = var.enable_velero ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "velero"
  service_account = "velero"
  role_arn        = aws_iam_role.velero[0].arn
}

resource "helm_release" "velero" {
  count = var.enable_velero ? 1 : 0

  name             = "velero"
  namespace        = "velero"
  create_namespace = true
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  version          = var.velero_chart_version

  values = [
    yamlencode({
      initContainers = [
        {
          name  = "velero-plugin-for-aws"
          image = "velero/velero-plugin-for-aws:v1.11.0"
          volumeMounts = [
            { mountPath = "/target", name = "plugins" }
          ]
        }
      ]
      configuration = {
        backupStorageLocation = [
          {
            name     = "default"
            provider = "aws"
            bucket   = var.velero_bucket_name
            config   = { region = var.region }
          }
        ]
        volumeSnapshotLocation = [
          {
            name     = "default"
            provider = "aws"
            config   = { region = var.region }
          }
        ]
      }
      schedules = var.velero_backup_schedules
      serviceAccount = {
        server = {
          annotations = {} # Pod Identity association above handles auth, no IRSA annotation needed
        }
      }
      tolerations = [
        { key = "node-role", operator = "Equal", value = "core", effect = "NoSchedule" }
      ]
      nodeSelector = { "node-role" = "core" }
    })
  ]

  depends_on = [aws_eks_pod_identity_association.velero]
}

# --- external-secrets: read from Secrets Manager / Parameter Store ---
resource "aws_iam_role" "external_secrets" {
  name = "${var.cluster_name}-external-secrets"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "secrets-read"
  role = aws_iam_role.external_secrets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "ssm:GetParameter",
        "ssm:GetParameters",
      ]
      Resource = "*"
    }]
  })
}

# --- Fluent Bit: write to CloudWatch Logs ---
resource "aws_iam_role" "fluent_bit" {
  name = "${var.cluster_name}-fluent-bit"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:logging:aws-for-fluent-bit"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "fluent_bit" {
  role       = aws_iam_role.fluent_bit.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# --- Default StorageClass: gp3, encrypted, WaitForFirstConsumer ---
resource "kubernetes_storage_class_v1" "gp3_default" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}
