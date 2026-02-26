module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.8.1" # Use the latest version

  name = "${var.project_name}-VPC"
  cidr = var.vpc_cidr

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"] # ALB, NAT gayeway
  private_subnets  = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"] # App - Worker Nodes
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"] # RDS, ElastiCache
  
  # NAT Gateway Strategy (Cost Optimized)
  enable_nat_gateway = true
  single_nat_gateway = true



  # Database Subnets Setup
  create_database_subnet_group           = true
  create_database_internet_gateway_route = false

  # DNS Support
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags for ALB Controller Discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  tags = {
    Terraform = "true"
    Environment = var.environment
    Project = var.project_name
  }

}

# S3 Gateway Endpoint - Allows FREE access to S3 from public and private subnets.
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  # Add the endpoint to the route tables
  route_table_ids = flatten([
    module.vpc.private_route_table_ids,
    module.vpc.public_route_table_ids
  ])

  tags = {
    Name        = "Nadav-S3-Gateway"
    Environment = var.environment
  }
}

