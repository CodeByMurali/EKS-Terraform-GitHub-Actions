locals {
  cluster_name = var.cluster-name
}

resource "random_integer" "random_suffix" {
  min = 1000
  max = 9999
}

# This role is used by the EKS control plane to create and manage AWS resources by assuming the specified role.
# When count is 0, Terraform effectively ignores the resource block, meaning no resources of that type are created or managed.
resource "aws_iam_role" "eks-cluster-role" {
  count = var.is_eks_role_enabled ? 1 : 0

  name  = "${local.cluster_name}-role-${random_integer.random_suffix.result}"
  # Vuit in json encder terraform function to convert the policy to a JSON string.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  count      = var.is_eks_role_enabled ? 1 : 0

# This policy allows the EKS control plane to manage AWS resources on your behalf, such as:  

# - **Auto Scaling**: Read/update configurations (for backward compatibility).  
# - **EC2**: Manage network/volume resources and provision EBS for Kubernetes.  
# - **ELB**: Provision load balancers and manage node targets.  
# - **IAM**: Create service-linked roles for dynamic resource management.  
# - **KMS**: Read keys for Kubernetes secrets encryption in etcd.  

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

# count.index is necessary to reference the specific element in the array created by the count argument.
# Even if only one role is created, Terraform requires the use of count.index to access the role's attributes.
  role       = aws_iam_role.eks-cluster-role[count.index].name
}

# This role is used by the EKS worker node group to interact with AWS services by assuming the specified role.
resource "aws_iam_role" "eks-nodegroup-role" {
  count = var.is_eks_nodegroup_role_enabled ? 1 : 0
  name  = "${local.cluster_name}-nodegroup-role-${random_integer.random_suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        # important: Not that the principal is set to ec2.amazonaws.com, not eks.amazonaws.com.
        # this means the the role can be assumed by the worker nodes.
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks-AmazonWorkerNodePolicy" {
  count      = var.is_eks_nodegroup_role_enabled ? 1 : 0

#   Attach the **AmazonEKSWorkerNodePolicy** to your worker nodes. This policy allows nodes to interact with required AWS services for effective operation, such as:

# - **ECR**: Pull container images required to run workloads on the nodes.  
# - **S3**: Access cluster logs and state files for operations like Kubernetes bootstrap.  
# - **EC2**: Retrieve instance metadata, manage instance tags, and interact with EC2 services.  

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks-nodegroup-role[count.index].name
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKS_CNI_Policy" {
  count      = var.is_eks_nodegroup_role_enabled ? 1 : 0

#   Attach the **AmazonEKS_CNI_Policy** to your worker nodes for Amazon VPC CNI plugin operations. It allows the CNI plugin to manage networking for EKS workloads, such as:

# - **EC2**: Assign, attach, and manage ENIs and IP addresses for pods.  
# - **EC2 Autoscaling**: Automatically scale and manage ENI capacity.  
# - **CloudWatch Logs**: Publish logs related to CNI plugin operations.  

#   No, the control plane does not need the AmazonEKS_CNI_Policy because the control plane is managed by Amazon EKS and is not directly involved in managing networking for pods 
#  in the same way worker nodes are.

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks-nodegroup-role[count.index].name
}


resource "aws_iam_role_policy_attachment" "eks-AmazonEC2ContainerRegistryReadOnly" {
  count      = var.is_eks_nodegroup_role_enabled ? 1 : 0

  # Attach the **AmazonEC2ContainerRegistryReadOnly** policy to worker nodes.
  # This policy allows the worker nodes to pull container images from ECR, enabling:
  # - **ECR**: Access to APIs for retrieving container images, such as `BatchGetImage` and `GetDownloadUrlForLayer`.
  # - Ensures nodes can retrieve application images stored in Amazon ECR.

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks-nodegroup-role[count.index].name
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEBSCSIDriverPolicy" {
  count      = var.is_eks_nodegroup_role_enabled ? 1 : 0

  # Attach the **AmazonEBSCSIDriverPolicy** policy to worker nodes.
  # This policy allows the nodes to use the Amazon EBS CSI driver for managing EBS volumes, enabling:
  # - **EBS**: Permissions to create, delete, attach, detach, and describe EBS volumes.
  # - **EC2**: Access required APIs for EBS volume operations.
  # - Supports dynamic provisioning and lifecycle management of Kubernetes PersistentVolumeClaims backed by EBS.

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.eks-nodegroup-role[count.index].name
}

# OIDC
# This IAM role allows only the EKS OIDC provider to assume the role.
# In this project we really dont use this role abywhere
# This is just to make sure the pods witht he service account can assume the role and access the AWS resources.
resource "aws_iam_role" "eks_oidc" {
  assume_role_policy = data.aws_iam_policy_document.eks_oidc_assume_role_policy.json
  name               = "eks-oidc"
}

# This is just a sample s3 policy to list and get buclets
# We will associate this policy to the eks_oidc role that we created above for testing purposes.
# In a real-world scenario, you would attach a policy that grants the necessary permissions to access your AWS resources.
# The pod that you create using the service account will have the permissions defined in the attached policy to list s3 buckets.
resource "aws_iam_policy" "eks-oidc-policy" {
  name = "test-policy"

  policy = jsonencode({
    Statement = [{
      Action = [
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation",
        "*"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
    Version = "2012-10-17"
  })
}

# This is whre you are attaching the S3 policy to the OIDC role.
# remember the OIDC role is also associated wiht the data.aws_iam_policy_document.eks_oidc_assume_role_policy.json
# which allows the pod withe the service account to assume the role.
# which inturn allows the pod to access the S3 bucket.

resource "aws_iam_role_policy_attachment" "eks-oidc-policy-attach" {
  role       = aws_iam_role.eks_oidc.name
  policy_arn = aws_iam_policy.eks-oidc-policy.arn
}

// Here is a sample of how you can create a service account and associate it with the OIDC role.
// annotations is the important part here. 
// The annotation eks.amazonaws.com/role-arn is used to associate the service account with the OIDC role that was created in AWS.
# apiVersion: v1
# kind: ServiceAccount
# metadata:
#   name: aws-test
#   namespace: default
#   annotations:
#     eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/eks-oidc

// This is how yoy attach the service account to the pod.
# apiVersion: v1
# kind: Pod
# metadata:
#   name: test-pod
#   namespace: default
# spec:
#   serviceAccountName: aws-test
#   containers:
#   - name: test-container
#     image: nginx
#     ports:
#     - containerPort: 80

// Remember the integration
// The pod that has the attached serce account will be able to assume the role that is attached to the OIDC role 
// Since we trust the OIDC role to assume the role
// Since we also attached the S3 policy to the OIDC role, the pod will be able to list the S3 buckets.