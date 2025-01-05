terraform {
  required_version = ">=1.10.3"
  backend "s3" {
    bucket         = "use1-remote-terraform-state-file-bucket"
    region         = "us-east-1"
    key            = "EKS-Jump/terraform.tfstate"
    dynamodb_table = "Project-2-Three-Tier-DevSecOps-Pipeline-Lock-Files-EKS"
    encrypt        = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.82.2"
    }
  }
}
