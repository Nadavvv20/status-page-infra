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
  value = aws_s3_bucket.app_assets.id
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