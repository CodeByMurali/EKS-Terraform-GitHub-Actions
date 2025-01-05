resource "aws_instance" "ec2_eks_jump" {
  ami                    = data.aws_ami.ami.image_id
  instance_type          = "t2.medium"
  key_name               = var.key-name
  subnet_id              = data.aws_subnet.public_subnet[0].id
  vpc_security_group_ids = [aws_security_group.eks_jump_sg.id]
  iam_instance_profile   = data.aws_iam_instance_profile.admin_access.name
  user_data              = templatefile("./jump-tools-install.sh", {})

  tags = {
    Name = var.instance-name
  }
}

resource "aws_security_group" "eks_jump_sg" {
  name        = var.eks-jump-sg
  description = "Security group for EKS jump host"
  vpc_id      = data.aws_vpc.eks-project-2-vpc.id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-project-2-jump-sg"
  }
}
