module "root_infrastructure" {
  source = "../../modules"

  region                 = var.region
  environment            = var.environment
  project_name           = "Nadav-Statuspage-Project-DEV"
  vpc_cidr               = var.vpc_cidr
  cluster_name           = "${var.cluster_name}-DEV"
  instance_types         = var.instance_types
  capacity_type          = var.capacity_type
  db_instance_class      = var.db_instance_class
  redis_node_type        = var.redis_node_type
  redis_engine_version   = var.redis_engine_version
  s3_bucket_name         = var.s3_bucket_name
  db_deletion_protection = var.db_deletion_protection
  enable_s3_assets       = var.enable_s3_assets
}