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