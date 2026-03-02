# EKS aws-auth ConfigMap Update
# This adds the GitHub Actions IAM role to the EKS cluster RBAC

# Note: This requires the kubernetes provider to be configured
# Make sure you have kubectl configured before running this

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# Data source to get existing aws-auth configmap
data "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
}

# Update aws-auth ConfigMap with GitHub Actions role
resource "kubernetes_config_map_v1_data" "aws_auth_github_actions" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  force = true

  data = {
    mapRoles = yamlencode(concat(
      # Parse existing roles
      yamldecode(lookup(data.kubernetes_config_map.aws_auth.data, "mapRoles", "[]")),
      
      # Add GitHub Actions role
      [
        {
          rolearn  = var.github_actions_role_arn
          username = "github-actions-deployer"
          groups   = ["system:masters"]  # Full admin for simplicity
        }
      ]
    ))
    
    # Keep existing mapUsers if any
    mapUsers = lookup(data.kubernetes_config_map.aws_auth.data, "mapUsers", "")
  }

  depends_on = [data.kubernetes_config_map.aws_auth]
}

# ==============================================================================
# Alternative: Using RBAC (Production-Ready)
# ==============================================================================

# Instead of system:masters, create a custom ClusterRole with specific permissions

resource "kubernetes_cluster_role" "github_actions_deployer" {
  metadata {
    name = "github-actions-deployer"
  }

  # Deployments
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Pods
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log"]
    verbs      = ["get", "list", "watch"]
  }

  # Services
  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  # ConfigMaps & Secrets
  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  # Ingress
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  # HPA
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
}

resource "kubernetes_cluster_role_binding" "github_actions_deployer" {
  metadata {
    name = "github-actions-deployer"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.github_actions_deployer.metadata[0].name
  }

  subject {
    kind      = "User"
    name      = "github-actions-deployer"
    api_group = "rbac.authorization.k8s.io"
  }
}

# ==============================================================================
# Variables
# ==============================================================================

variable "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  type        = string
}

# ==============================================================================
# Outputs
# ==============================================================================

output "aws_auth_updated" {
  description = "Confirmation that aws-auth was updated"
  value       = "GitHub Actions role added to aws-auth ConfigMap"
}
