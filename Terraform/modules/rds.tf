# RDS Instance
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = lower("${var.project_name}-db")

  engine               = "postgres"
  engine_version       = "15" # Requirement: 10 or above
  family               = "postgres15"
  major_engine_version = "15"
  instance_class       = var.db_instance_class

  allocated_storage = 20
  manage_master_user_password = false

  db_name  = "statuspage"
  username = "statuspage"
  password = random_password.db_password.result
  port     = 5432

  multi_az               = true # For high availability
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  deletion_protection = var.db_deletion_protection 
  skip_final_snapshot = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}