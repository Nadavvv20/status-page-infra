data "aws_caller_identity" "current" {}

# S3 for Prometheus and Loki
resource "aws_s3_bucket" "monitoring_data" {
  bucket        = "monitoring-data-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# EFS for Grafana
resource "aws_efs_file_system" "grafana_storage" {
  creation_token   = "grafana-efs"
  encrypted        = true
  performance_mode = "generalPurpose"
}

# Allow     
resource "aws_security_group" "efs_sg" {
  name        = "grafana-efs-sg"
  vpc_id      = module.vpc.default_vpc_id 

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id] 
  }
}

resource "aws_efs_mount_target" "grafana_efs_mt" {
  count           = length(module.vpc.private_subnets) 
  file_system_id  = aws_efs_file_system.grafana_storage.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs_sg.id]
}

resource "aws_s3_bucket_lifecycle_configuration" "monitoring_data_lifecycle" {
  bucket = aws_s3_bucket.monitoring_data.id

  rule {
    id     = "delete-old-monitoring-data"
    status = "Enabled"

    expiration {
      days = 14 # Deletes files that are 14 days old
    }
  }
}