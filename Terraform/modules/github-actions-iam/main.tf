# GitHub Actions IAM Module for AWS

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "app_repo_name" {
  description = "Application repository name"
  type        = string
  default     = "status-page-app"
}

variable "infra_repo_name" {
  description = "Infrastructure repository name"
  type        = string
  default     = "status-page-infra"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

# ==============================================================================
# OIDC Provider for GitHub Actions
# ==============================================================================

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # GitHub's thumbprints (valid as of 2024)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name    = "${var.project_name}-github-oidc-provider"
    Project = var.project_name
  }
}

# ==============================================================================
# IAM Role for GitHub Actions
# ==============================================================================

# Trust policy - allow GitHub Actions to assume this role
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only allow specific repos to assume this role
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.app_repo_name}:*",
        "repo:${var.github_org}/${var.infra_repo_name}:*"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions_deployer" {
  name               = "${var.project_name}-github-actions-deployer"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name    = "${var.project_name}-github-actions-deployer"
    Project = var.project_name
  }
}

# ==============================================================================
# ECR Permissions - Push/Pull Docker images
# ==============================================================================

data "aws_iam_policy_document" "ecr_permissions" {
  # ECR Authentication
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  # ECR Repository Access
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:ListImages"
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_policy" "ecr_permissions" {
  name        = "${var.project_name}-github-actions-ecr"
  description = "Allows GitHub Actions to push/pull images to ECR"
  policy      = data.aws_iam_policy_document.ecr_permissions.json

  tags = {
    Name    = "${var.project_name}-github-actions-ecr"
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "ecr_permissions" {
  role       = aws_iam_role.github_actions_deployer.name
  policy_arn = aws_iam_policy.ecr_permissions.arn
}

# ==============================================================================
# EKS Permissions - Deploy to Kubernetes
# ==============================================================================

data "aws_iam_policy_document" "eks_permissions" {
  # EKS Cluster Access
  statement {
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
      "eks:ListClusters",
      "eks:DescribeNodegroup",
      "eks:ListNodegroups",
      "eks:AccessKubernetesApi"
    ]
    resources = ["*"]
  }

  # Additional permissions for kubectl
  statement {
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "eks_permissions" {
  name        = "${var.project_name}-github-actions-eks"
  description = "Allows GitHub Actions to access EKS cluster"
  policy      = data.aws_iam_policy_document.eks_permissions.json

  tags = {
    Name    = "${var.project_name}-github-actions-eks"
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "eks_permissions" {
  role       = aws_iam_role.github_actions_deployer.name
  policy_arn = aws_iam_policy.eks_permissions.arn
}

# ==============================================================================
# Outputs
# ==============================================================================

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions (use in GitHub Secrets)"
  value       = aws_iam_role.github_actions_deployer.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions_deployer.name
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

# ==============================================================================
# Instructions Output
# ==============================================================================

output "setup_instructions" {
  description = "Instructions for completing the setup"
  value = <<-EOT
    
    ✅ Terraform resources created successfully!
    
    📋 Next Steps:
    
    1. Add to GitHub Secrets (both repos):
       - Secret Name: AWS_ROLE_ARN
       - Secret Value: ${aws_iam_role.github_actions_deployer.arn}
    
    2. Update EKS aws-auth ConfigMap:
       kubectl edit configmap aws-auth -n kube-system
       
       Add this to mapRoles:
       - rolearn: ${aws_iam_role.github_actions_deployer.arn}
         username: github-actions-deployer
         groups:
           - system:masters
    
    3. Update workflow files:
       - Set github_org: ${var.github_org}
       - Set eks_cluster_name: ${var.eks_cluster_name}
    
    4. Create GitHub PAT:
       - Go to: https://github.com/settings/tokens/new
       - Scopes: repo, workflow
       - Add to both repos as PAT_TOKEN
    
    5. Test the pipeline:
       git push origin main
    
    🎉 Happy deploying!
  EOT
}
