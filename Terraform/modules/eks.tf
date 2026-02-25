module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  # Allows access from the internet to run 'kubectl' commands
  cluster_endpoint_public_access = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Allows the pods to receive IRSA
  enable_irsa = true

  # Worker Nodes configuration
  eks_managed_node_groups = {
    app_nodes = {
      min_size     = 1
      max_size     = 4
      desired_size = 2

      instance_types = var.instance_types
      capacity_type  = var.capacity_type

      # Connect only to the private app subnets
      subnet_ids = module.vpc.private_subnets

      tags = {
        NodeGroup = "app-nodes"
        "k8s.io/cluster-autoscaler/enabled"              = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      }
    }
  }

  enable_cluster_creator_admin_permissions = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Role for the Autoscaler (Using IRSA)
module "cluster_autoscaler_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                        = "cluster-autoscaler-role-nadav"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_ids   = [module.eks.cluster_name]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}