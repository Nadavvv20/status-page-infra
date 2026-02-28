output "cluster_name" {
  value = module.eks.cluster_name
}

output "rds_endpoint" {
  value = module.db.db_instance_address
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "s3_bucket_name" {
  value = aws_s3_bucket.app_assets.id
}

output "load_balancer_controller_role_arn" {
  value = module.load_balancer_controller_irsa_role.iam_role_arn
}

output "alb_security_group_id" {
  value = aws_security_group.alb_sg.id
}