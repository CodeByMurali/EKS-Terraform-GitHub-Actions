output "ec2_eks_instance_id" {
  value = aws_instance.ec2_eks_jump.id
}

output "ec2_eks_instance_public_ip" {
  value = aws_instance.ec2_eks_jump.public_ip
}
