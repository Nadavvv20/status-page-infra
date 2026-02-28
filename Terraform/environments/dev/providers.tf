# providers.tf
terraform {
    # Specifies the required Terraform CLI version
  required_version = ">= 1.2"

  required_providers {
    # Define the AWS provider requirement
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
        }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
    }
    # Save the state in S3 for data durability
    backend "s3" {
    bucket         = "nadav-tfstate-bucket" 
    key            = "dev/terraform.tfstate" 
    region         = "us-east-1"                          
    encrypt        = true                                 
  }
}
# Configure the default AWS provider
provider "aws" {
  region = "us-east-1"
}
provider "helm" {
  kubernetes = {
    host                   = module.root_infrastructure.cluster_endpoint
    cluster_ca_certificate = base64decode(module.root_infrastructure.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      args        = ["eks", "get-token", "--cluster-name", module.root_infrastructure.cluster_name]
      command     = "aws"
    }
  }
}
  