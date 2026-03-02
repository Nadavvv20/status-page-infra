variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
}

variable "load_balancer_controller_role_arn" {
  description = "Role ARN for AWS Load Balancer Controller"
  type        = string
}

variable "external_secrets_irsa_role_arn" {
  description = "Role ARN for External Secrets Operator"
  type        = string
}

variable "cluster_autoscaler_irsa_role_arn" {
  description = "Role ARN for Cluster Autoscaler"
  type        = string
}

variable "rds_address" {
  description = "RDS Address"
  type        = string
}

variable "redis_address" {
  description = "Redis primary endpoint"
  type        = string
}

variable "django_secret_name" {
  description = "Django secret name in AWS Secrets Manager"
  type        = string
}

variable "db_password_secret_name" {
  description = "DB password secret name in AWS Secrets Manager"
  type        = string
}

variable "django_admin_secret_name" {
  description = "Django admin secret name in AWS Secrets Manager"
  type        = string
}
