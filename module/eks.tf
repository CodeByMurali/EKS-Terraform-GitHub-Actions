resource "aws_eks_cluster" "eks" {

# conditionally creates the resource based on whether var.is-eks-cluster-enabled is true. If true, one instance is created; otherwise, none.
  count    = var.is-eks-cluster-enabled == true ? 1 : 0
  name     = var.cluster-name
  # This role is used by the EKS control plane to create and manage AWS resources by assuming the specified role.
  role_arn = aws_iam_role.eks-cluster-role[count.index].arn
  version  = var.cluster-version

  # The vpc_config block is a nested block that configures the VPC settings for the EKS cluster.
  # It is available by default in the aws_eks_cluster resource provided by the AWS provider.
  vpc_config {

    # By specifying these ptivate subnet IDs, the EKS cluster control plane resources will be deployed within these private subnets
    subnet_ids              = [
      aws_subnet.private-subnet[0].id, 
      aws_subnet.private-subnet[1].id, 
      aws_subnet.private-subnet[2].id
      ]
    
    # This is set to true to allow the EKS cluster to communicate with private IP addresses in the VPC.
    # We will be using a bastion host to access the EKS cluster that is deployed in the private subnets.
    endpoint_private_access = var.endpoint-private-access

    # This is set to false to prevent the EKS cluster from communicating with the public internet.
    # if set to true, the EKS cluster will have a public endpoint that can be accessed from the internet.
    endpoint_public_access  = var.endpoint-public-access

    # By default used the main security group of the VPC which allows all traffic.
    # But we are using a custom security group for the EKS cluster
    security_group_ids      = [aws_security_group.eks-cluster-sg.id]
  }

  # authentication_mode: Specifies the mode of authentication. 
  #   - "CONFIG_MAP": Uses a Kubernetes ConfigMap for authentication.
  #   - "IAM": Uses AWS IAM for authentication.
  # bootstrap_cluster_creator_admin_permissions: 
  # Grants admin permissions to the user who created the cluster.
  access_config {
    authentication_mode                         = "CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

# Needed to explicity define the depends_on argument to ensure that the EKS cluster is created 
# after the IAM role policy attachment for the EKS cluster policy is created.

# If not declared, EKS will not be able to properly delete EKS managed EC2 infrastructure.
  depends_on = [ 
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy 
  ]

  tags = {
    Name = var.cluster-name
    Env  = var.env
  }
}

# OIDC Provider
# You can either attach IAM role to the EKS node in that case all the pods in that node will have the same IAM permissions.
# However, if you would like you application pods to have permissions based on the serveice account, you can use the OIDC provider.

# TLS certificates ensure that the communication between the Kubernetes control plane and the worker nodes is secure.
resource "aws_iam_openid_connect_provider" "eks-oidc" {
  client_id_list  = ["sts.amazonaws.com"]
// Obtain the SHA-1 fingerprint (thumbprint) of the TLS certificate for the EKS cluster.
// This thumbprint is used to verify the authenticity of the certificate.
thumbprint_list = [data.tls_certificate.eks-certificate.certificates[0].sha1_fingerprint]

// Obtain the URL of the EKS cluster's API server.
// This URL is used to interact with the EKS cluster.
url = data.tls_certificate.eks-certificate.url
}

# AddOns for EKS Cluster
resource "aws_eks_addon" "eks-addons" {
  for_each      = { for idx, addon in var.addons : idx => addon }
  cluster_name  = aws_eks_cluster.eks[0].name
  addon_name    = each.value.name
  addon_version = each.value.version

  depends_on = [
    aws_eks_node_group.ondemand-node,
    aws_eks_node_group.spot-node
  ]
}

# NodeGroups

# EKS provisions both node types by creating separate node groups for each type. 
# In this configuration, we have defined two node groups:

# aws_eks_node_group.ondemand-node for on-demand instances.
# aws_eks_node_group.spot-node for spot instances.
# Cluster Association: Both node groups are associated with the same EKS cluster, 
# as indicated by the cluster_name attribute.

# The configuration uses aws_eks_node_group, creating managed node groups.
# Node Types: Defines:
# On-demand node group (ondemand-node).
# Spot node group (spot-node).

# Autoscaling: Enabled via scaling_config for desired, min, and max sizes.
# Cluster Autoscaler: Not explicitly configured. Needs to be deployed as an add-on with appropriate IAM permissions.


resource "aws_eks_node_group" "ondemand-node" {
  # Since we are creating the EKS cluster conditionally, 
  # we need to get the name of the EKS cluster from the first element of the list.
  cluster_name    = aws_eks_cluster.eks[0].name
  node_group_name = "${var.cluster-name}-on-demand-nodes"

  node_role_arn = aws_iam_role.eks-nodegroup-role[0].arn

  scaling_config {
    desired_size = var.desired_capacity_on_demand
    min_size     = var.min_capacity_on_demand
    max_size     = var.max_capacity_on_demand
  }

 # The worker nodes will be deployed in the private subnets
 # The public subnets are used for the bastion host, NAT gateway and the load balancer.
  subnet_ids = [
    aws_subnet.private-subnet[0].id, 
    aws_subnet.private-subnet[1].id, 
    aws_subnet.private-subnet[2].id
    ]

  # default is set to t3a.medium
  instance_types = var.ondemand_instance_types

  # valid values are SPOT or ON_DEMAND
  capacity_type  = "ON_DEMAND"
  
  # The labels block is used to assign metadata to the EKS resources.
  #  These labels are added to the nodes within the EKS node group and 
  #  can be used by Kubernetes for various purposes, such as scheduling, organizing, and managing nodes.
  # Eg: kubectl get nodes --show-labels
  # This will also be used by the kubernetes scwerduler to schedule the pods on the nodes based on the labels. Node affinity and anti-affinity.
  labels = {
    type = "ondemand"
  }

  # The `update_config` block is used to configure the update settings for the EKS cluster.
  # The `max_unavailable` attribute specifies the maximum number of nodes that can be unavailable
  # during the update process. In this case, it is set to 1, meaning that only one node can be
  # unavailable at any given time during the update.
  update_config {
    max_unavailable = 1
  }

  tags = {
    "Name" = "${var.cluster-name}-ondemand-nodes"
  }

  depends_on = [aws_eks_cluster.eks]

  # Other optional configurations

  # AMI type for the worker nodes is not needed as we are using the latest EKS optimized AMI.
  # Possible options are AL2_x86_64, AL2_x86_64_GPU, AL2_ARM_64, AL2_ARM_64_GPU
  # default disk size is 20GB
  # force_version_update = false - if existing pods are unable to drain due to a pod disruption budget issue,
  # the update will fail.

  # declare taints to the node group
  # taint {
  #   key = "team"
  #   value = "DevOps"
  #   effect = "NO_SCHEDULE"
  # }

  # Use launch template to use custom configuration the worker nodes
  # launch_template {
  #   name = "eks-nodegroup-launch-template"
  #   version = "$Latest"
  #   id = aws_launch_template.eks-nodegroup-launch-template.id
  # }

  # Configure disk size for the worker nodes
  # disk_size = 50
  # ebs {
  #   volume_size = 50
  #   volume_type = "gp2"
  # }
}

resource "aws_eks_node_group" "spot-node" {
  cluster_name    = aws_eks_cluster.eks[0].name
  node_group_name = "${var.cluster-name}-spot-nodes"

  node_role_arn = aws_iam_role.eks-nodegroup-role[0].arn

  # EKS will make use of this config to create ASG for the worker nodes.
  scaling_config {
    desired_size = var.desired_capacity_spot
    min_size     = var.min_capacity_spot
    max_size     = var.max_capacity_spot
  }


  subnet_ids = [
    aws_subnet.private-subnet[0].id,
     aws_subnet.private-subnet[1].id, 
     aws_subnet.private-subnet[2].id
     ]

  instance_types = var.spot_instance_types
  capacity_type  = "SPOT"

  update_config {
    max_unavailable = 1
  }
  tags = {
    "Name" = "${var.cluster-name}-spot-nodes"
  }
  labels = {
    type      = "spot"
    lifecycle = "spot"
  }
  disk_size = 50

  depends_on = [
    aws_eks_cluster.eks,
    # otherwise EKS will not be able to properly delete EKS managed EC2 infrastructure and ENI.
    aws_iam_role_policy_attachment.eks-AmazonWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-AmazonEC2ContainerRegistryReadOnly
    ]
}

    # Unamanged node group notes:
    # Unmanaged Node Group: Nodes are launched in an ASG, not directly managed by EKS.
    # IAM Role: Attach AmazonEKSWorkerNodePolicy for node IAM permissions.
    # Cluster Integration: Tag instances with kubernetes.io/cluster/<cluster-name> as owned or shared.
    # Autoscaling: The ASG manages scaling, not the EKS control plane.
    # Steps: Create ASG, attach IAM policy, tag instances, and configure autoscaling.
    # 1. Create a Launch Template for EC2 instances.  
    # 2. Create an Auto Scaling Group with the Launch Template.  
    # 3. Tag instances with `kubernetes.io/cluster/<cluster-name>` as `owned`.  
    # 4. Attach IAM Role with `AmazonEKSWorkerNodePolicy` to the nodes.  
    # 5. Associate the ASG with the EKS cluster.  