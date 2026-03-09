resource "kubernetes_config_map_v1" "statuspage_config" {
  metadata {
    name      = "statuspage-app-config"
    namespace = "statuspage"
  }

  data = {
    # App Settings
    DJANGO_DEBUG   = "False"
    ALLOWED_HOSTS  = "*"
    AWS_REGION     = var.region
    AWS_S3_REGION_NAME = var.region
    AWS_STORAGE_BUCKET_NAME = var.enable_s3_assets ? aws_s3_bucket.app_assets[0].bucket : ""
    USE_S3         = var.enable_s3_assets ? "True" : "False"

    # Secret Names
    DJANGO_SECRET_NAME       = aws_secretsmanager_secret.django_secret.name
    DB_PASSWORD_SECRET_NAME  = aws_secretsmanager_secret.db_password.name
    DJANGO_ADMIN_SECRET_NAME = aws_secretsmanager_secret.django_admin_secret.name

    DB_ENGINE = "django.db.backends.postgresql"
    DB_NAME   = "statuspage"
    DB_USER   = "statuspage"
    DB_HOST   = module.db.db_instance_address
    DB_PORT   = "5432"

    REDIS_HOST        = aws_elasticache_replication_group.redis.primary_endpoint_address
    REDIS_PORT        = "6379"
    REDIS_TASKS_DB    = "0"
    REDIS_CACHING_DB  = "1"
  }

  depends_on = [
    module.db,
    aws_elasticache_replication_group.redis
  ]
}