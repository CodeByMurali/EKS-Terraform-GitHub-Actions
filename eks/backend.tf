terraform {
  required_version = ">=1.10.3"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.82.2"
    }
  }
  backend "s3" {
    bucket         = "use1-remote-terraform-state-file-bucket"
    region         = "us-east-1"
    key            = "Project-2-Three-Tier-DevSecOps-Pipeline-Lock-Files/EKS/terraform.tfstate"
    dynamodb_table = "Project-2-Three-Tier-DevSecOps-Pipeline-Lock-Files-EKS"
    encrypt        = true
  }
}

provider "aws" {
  region  = var.aws-region
}
