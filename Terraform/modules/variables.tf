variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "Nadav-Statuspage-Project"
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
  default     = "Nadav-Statuspage-EKS"
}

variable "instance_types" {
  description = "EC2 Instance types for Node Group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "capacity_type" {
  description = "EC2 Instance capacity type"
  type        = string
  default     = "ON_DEMAND"
}

variable "db_instance_class" {
  type        = string
  description = "The instance type for the RDS database"
}

variable "redis_node_type" {
  type        = string
description = "The instance type for the Redis cluster"
}

variable "redis_engine_version" {
  default = "7.0" # Requirement: 4 or above
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for app static files"
  type        = string
  default     = "nadav-statuspage-assets"
}

variable "db_deletion_protection" {
  description = "If true, the database cannot be deleted"
  type        = bool
}


variable "enable_s3_assets" {
  description = "Toggles the creation of S3 bucket and IRSA resources"
  type        = bool
}