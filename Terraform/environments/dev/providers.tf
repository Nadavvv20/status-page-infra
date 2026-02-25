# providers.tf file
terraform {
    # Specifies the required Terraform CLI version
  required_version = ">= 1.2"

  required_providers {
    # Define the AWS provider requirement
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
        }
    }
    # Save the state in S3 for data durability
    backend "s3" {
    bucket         = "nadav-tf-bucket " 
    key            = "dev/terraform.tfstate" 
    region         = "us-west-1"                          
    encrypt        = true                                 
  }
}
# Configure the default AWS provider
provider "aws" {
  region = "us-east-1"
}
  