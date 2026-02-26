# elasticache.tf
resource "aws_elasticache_subnet_group" "redis_subnets" {
  name       = "${var.project_name}-redis-group"
  subnet_ids = module.vpc.private_subnets
}
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "${var.project_name}-redis"
  description                   = "Redis for StatusPage task queue and cache"
  node_type                     = var.redis_node_type
  engine                        = "redis"
  engine_version                = var.redis_engine_version
  port                          = 6379
  parameter_group_name          = "default.redis7"
  automatic_failover_enabled    = true

  subnet_group_name = aws_elasticache_subnet_group.redis_subnets.name
  security_group_ids            = [aws_security_group.redis_sg.id]

  # Primary, and one replica in another AZ
  num_cache_clusters            = 2

  tags = {
    Name        = "${var.project_name}-redis"
    Environment = var.environment
  }
}