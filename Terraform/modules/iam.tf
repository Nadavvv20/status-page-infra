# ==================================================================
# S3 access policy:
resource "aws_iam_policy" "s3_access_policy" {
  count  = var.enable_s3_assets ? 1 : 0
  name        = "${var.project_name}-s3-access"
  description = "Allow Django pods to access S3 assets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:DeleteObject"]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.app_assets[0].arn,
          "${aws_s3_bucket.app_assets[0].arn}/*"
        ]
      }
    ]
  })
}
module "statuspage_app_irsa" {
  count  = var.enable_s3_assets ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-app-s3-role"
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["statuspage:statuspage-sa"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "app_s3_attach" {
  count  = var.enable_s3_assets ? 1 : 0
  role       = module.statuspage_app_irsa[0].iam_role_name
  policy_arn = aws_iam_policy.s3_access_policy[0].arn
}

# ===============================================================
# AWS Load Balancer Controller IRSA Role:
module "load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.project_name}-lb-controller-role"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# ===============================================================
# Cluster Autoscaler IRSA Role:
module "cluster_autoscaler_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                        = "${var.project_name}-cluster-autoscaler-role"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_ids   = [module.eks.cluster_name]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}

#========================================================
# Policy for ESO to access secrets
resource "aws_iam_policy" "secrets_read_policy" {
  name        = "${var.project_name}-secrets-read"
  description = "Allow reading secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [  
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.django_secret.arn,
          aws_secretsmanager_secret.django_admin_secret.arn,
          data.aws_secretsmanager_secret.grafana_github_auth.arn
        ]
      }
    ]
  })
}
module "external_secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-external-secrets-role"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    secrets_read = aws_iam_policy.secrets_read_policy.arn
  }
}
resource "aws_iam_role_policy_attachment" "secrets_attach" {
  role       = module.external_secrets_irsa_role.iam_role_name
  policy_arn = aws_iam_policy.secrets_read_policy.arn
}

#############################################
# Github auth secret
data "aws_secretsmanager_secret" "grafana_github_auth" {
  name = "nadav-grafana/github-auth"
}
####################################
# --- IAM Role for EBS CSI Driver ---
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}
resource "aws_iam_role" "ebs_csi_irsa" {
  name               = "${var.cluster_name}-ebs-csi-irsa"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_irsa.name
}

 # --- IAM Role for VPC CNI (aws-node) ---
data "aws_iam_policy_document" "vpc_cni_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }
  }
}

resource "aws_iam_role" "vpc_cni_irsa" {
  name               = "${var.cluster_name}-vpc-cni-irsa"
  assume_role_policy = data.aws_iam_policy_document.vpc_cni_assume_role.json
}

resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni_irsa.name
}

resource "aws_iam_policy" "eks_describe_addon" {
  name        = "EKSDescribeAddonPolicy"
  description = "Allows nodes to describe addons for AL2023 capacity calculation"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["eks:DescribeAddon"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

##################################################################
# IAM Roles (IRSA) For Prometheus and Loki to access the S3 bucket
data "aws_iam_policy_document" "monitoring_s3_access" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = [
      aws_s3_bucket.monitoring_data.arn,
      "${aws_s3_bucket.monitoring_data.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "monitoring_s3_policy" {
  name   = "MonitoringS3AccessPolicy"
  policy = data.aws_iam_policy_document.monitoring_s3_access.json
}

resource "aws_iam_role" "thanos_irsa" {
  name = "thanos-s3-irsa"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Condition = {
        "StringEquals" = {
          "${replace(module.eks.oidc_provider, "https://", "")}:sub" = "system:serviceaccount:monitoring:prometheus-prometheus-stack-kube-prom-prometheus"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "thanos_s3" {
  role       = aws_iam_role.thanos_irsa.name
  policy_arn = aws_iam_policy.monitoring_s3_policy.arn
}

resource "aws_iam_role" "loki_irsa" {
  name = "loki-s3-irsa"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Condition = {
        "StringEquals" = {
          "${replace(module.eks.oidc_provider, "https://", "")}:sub" = "system:serviceaccount:monitoring:loki"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "loki_s3" {
  role       = aws_iam_role.loki_irsa.name
  policy_arn = aws_iam_policy.monitoring_s3_policy.arn
}