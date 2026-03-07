module "root_infrastructure" {
  source = "../../modules"

  region                 = var.region
  environment            = var.environment
  project_name           = "Nadav-Statuspage-Project-PROD"
  vpc_cidr               = var.vpc_cidr
  cluster_name           = "${var.cluster_name}-PROD"
  instance_types         = var.instance_types
  capacity_type          = var.capacity_type
  db_instance_class      = var.db_instance_class
  redis_node_type        = var.redis_node_type
  redis_engine_version   = var.redis_engine_version
  s3_bucket_name         = var.s3_bucket_name
  db_deletion_protection = var.db_deletion_protection
  enable_s3_assets       = var.enable_s3_assets
}

module "helm_releases" {
  source = "../../modules/helm_releases"

  region                            = var.region
  cluster_name                      = module.root_infrastructure.cluster_name
  load_balancer_controller_role_arn = module.root_infrastructure.load_balancer_controller_role_arn
  external_secrets_irsa_role_arn    = module.root_infrastructure.external_secrets_irsa_role_arn
  cluster_autoscaler_irsa_role_arn  = module.root_infrastructure.cluster_autoscaler_irsa_role_arn
  rds_address                       = module.root_infrastructure.rds_address
  redis_address                     = module.root_infrastructure.redis_address
  django_secret_name                = module.root_infrastructure.django_secret_name
  db_password_secret_name           = module.root_infrastructure.db_password_secret_name
  django_admin_secret_name          = module.root_infrastructure.django_admin_secret_name
  thanos_irsa_role_arn              = module.root_infrastructure.thanos_irsa_role_arn
  thanos_objstore_secret_name       = module.root_infrastructure.thanos_objstore_secret_name
  loki_irsa_role_arn                = module.root_infrastructure.loki_irsa_role_arn
  monitoring_data_bucket_id         = module.root_infrastructure.monitoring_data_bucket_id
}