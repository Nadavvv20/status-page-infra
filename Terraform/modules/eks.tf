module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.32"

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
      min_size     = 3
      max_size     = 4
      desired_size = 3

      instance_types = var.instance_types
      capacity_type  = var.capacity_type

      # Connect only to the private app subnets
      subnet_ids = module.vpc.private_subnets

      tags = {
        NodeGroup = "app-nodes"
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
        "kubernetes.io/cluster/${var.cluster_name}"     = "owned"
        Name = "${var.project_name}-Worker-Node"
      }
    }
  }

  enable_cluster_creator_admin_permissions = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}