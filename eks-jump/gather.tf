data "aws_ami" "ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

data "aws_vpc" "eks-project-2-vpc" {
  filter {
    name   = "tag:Name"
    values = ["dev-Project-2-Three-Tier-DevSecOps-Pipeline-vpc"]
  }
}

data "aws_iam_instance_profile" "admin_access" {
  name = var.eks-jump-instance-profile
}

# Use the VPC ID in other resources
data "aws_subnets" "public" {
  filter {
    name   = "tag:kubernetes.io/role/elb"
    values = ["1"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eks-project-2-vpc.id]
  }
}

data "aws_subnet" "public_subnet" {
  for_each = toset(data.aws_subnets.public.ids)
  id       = each.value
}

