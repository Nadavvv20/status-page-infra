# modules/outputs.tf

output "cluster_name" {
  value = module.eks.cluster_name
}

output "rds_address" {
  value = module.db.db_instance_address
}

output "redis_address" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}


output "s3_bucket_id" {
  value = var.enable_s3_assets ? resource.aws_s3_bucket.app_assets[0].id : "Bucket not created"
}

output "lbc_role_arn" {
  value = module.load_balancer_controller_irsa_role.iam_role_arn
}

output "alb_sg_id" {
  value = aws_security_group.alb_sg.id
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}


output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "load_balancer_controller_role_arn" {
  description = "The ARN of the IAM role for the LB Controller"
  value       = module.load_balancer_controller_irsa_role.iam_role_arn
}

output "external_secrets_irsa_role_arn" {
  description = "The ARN of the IAM role for External Secrets"
  value       = module.external_secrets_irsa_role.iam_role_arn
}

output "statuspage_app_irsa_arn" {
  description = "The ARN of the IAM role for the statuspage app pods"
  value       = one(module.statuspage_app_irsa[*].iam_role_arn)
}

output "cluster_autoscaler_irsa_role_arn" {
  description = "The ARN of the IAM role for the cluster autoscaler"
  value       = module.cluster_autoscaler_irsa_role.iam_role_arn
}

output "db_password_secret_name" {
  description = "The name of the DB password secret"
  value       = aws_secretsmanager_secret.db_password.name
}

output "django_secret_name" {
  description = "The name of the Django secret"
  value       = aws_secretsmanager_secret.django_secret.name
}

output "django_admin_secret_name" {
  description = "The name of the Django admin credentials secret"
  value       = aws_secretsmanager_secret.django_admin_secret.name
}

output "thanos_irsa_role_arn" { value = aws_iam_role.thanos_irsa.arn }
output "thanos_objstore_secret_name" { value = kubernetes_secret.thanos_objstore.metadata[0].name }
output "loki_irsa_role_arn" { value = aws_iam_role.loki_irsa.arn }
output "monitoring_data_bucket_id" { value = aws_s3_bucket.monitoring_data.id }
