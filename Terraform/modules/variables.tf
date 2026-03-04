variable "region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
}

variable "instance_types" {
  description = "EC2 Instance types for Node Group"
  type        = list(string)
}

variable "capacity_type" {
  description = "EC2 Instance capacity type"
  type        = string
}

variable "db_instance_class" {
  description = "The instance type for the RDS database"
  type        = string
}

variable "redis_node_type" {
  description = "The instance type for the Redis cluster"
  type        = string
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for app static files"
  type        = string
}

variable "db_deletion_protection" {
  description = "If true, the database cannot be deleted"
  type        = bool
}

variable "enable_s3_assets" {
  description = "Toggles the creation of S3 bucket and IRSA resources"
  type        = bool
}

