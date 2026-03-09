# environments/prod/outputs.tf

output "cluster_name" {
  value = module.root_infrastructure.cluster_name
}

output "rds_endpoint" {
  value = module.root_infrastructure.rds_address
}

output "redis_endpoint" {
  value = module.root_infrastructure.redis_address
}

output "s3_bucket_name" {
  value = module.root_infrastructure.s3_bucket_id
}
