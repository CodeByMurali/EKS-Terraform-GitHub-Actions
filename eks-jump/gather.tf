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

data "aws_subnet_ids" "public" {
  vpc_id = var.vpc_id
  tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

data "aws_subnet" "public_subnet" {
  for_each = toset(data.aws_subnet_ids.public.ids)
  id       = each.value
}
