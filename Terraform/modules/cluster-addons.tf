# --- EBS CSI Driver Add-on ---
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi_irsa.arn
  resolve_conflicts_on_update = "OVERWRITE"
}

# StorageClass configuration
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    type = "gp3"
  }
  depends_on = [module.eks]
}

 # This allows each t3.medium node to have 110 IP adresses for pods instead of only 17
# --- VPC CNI Add-on ---
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.19.2-eksbuild.1"
  service_account_role_arn    = aws_iam_role.vpc_cni_irsa.arn
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })
}

#######################################################################3

# Storage class for EFS
resource "kubernetes_storage_class_v1" "efs_sc" {
  metadata {
    name = "efs-sc"
  }
  storage_provisioner = "efs.csi.aws.com"
  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.grafana_storage.id
    directoryPerms   = "700"
  }
}

# Set S3 monitoring Bucket configurations for Thanos
resource "kubernetes_secret" "thanos_objstore" {
  metadata {
    name      = "thanos-objstore-config"
    namespace = "monitoring"
  }
  data = {
    "thanos.yaml" = yamlencode({
      type = "s3"
      config = {
        bucket   = aws_s3_bucket.monitoring_data.id
        endpoint = "s3.${var.region}.amazonaws.com"
        prefix   = "thanos/"
      }
    })
  }
}