############################################################
# DB Password:
# 1. Create strong password
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# 2. Create the 'secret' in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.project_name}-db-password-${var.environment}"
  description = "RDS Database password for StatusPage"
  
  recovery_window_in_days = 0 

  tags = {
    Environment = var.environment
  }
}

# 3. Inject the password into the secret
resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

###############################################################
# Django Secret Key:
resource "random_password" "django_secret_key" {
  length  = 50
  special = true
}

resource "aws_secretsmanager_secret" "django_secret" {
  name                    = "${var.project_name}-django-secret-${var.environment}"
  description = "Django secret key"

  recovery_window_in_days = 0 
}

resource "aws_secretsmanager_secret_version" "django_secret_version" {
  secret_id     = aws_secretsmanager_secret.django_secret.id
  secret_string = random_password.django_secret_key.result
}
################################################################
# Superuser Password:
resource "random_password" "django_admin_password" {
  length  = 20
  special = true
}

resource "aws_secretsmanager_secret" "django_admin_secret" {
  name                    = "${var.project_name}-admin-credentials-${var.environment}"
  recovery_window_in_days = 0 
}

resource "aws_secretsmanager_secret_version" "django_admin_secret_version" {
  secret_id     = aws_secretsmanager_secret.django_admin_secret.id
  secret_string = random_password.django_admin_password.result
}