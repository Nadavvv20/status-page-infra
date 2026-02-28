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

