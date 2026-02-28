module "root_infrastructure" {
  source = "../../modules"

  environment    = var.environment
  project_name   = "Nadav-Statuspage-Project-DEV"
  db_deletion_protection = var.db_deletion_protection
  redis_node_type = var.redis_node_type
  db_instance_class = var.db_instance_class
  enable_s3_assets = var.enable_s3_assets
}