# Let's break down how a Kubernetes service account integrates with an IAM role in the context of Amazon EKS

# Overview
# In Amazon EKS, you can associate an IAM role with a Kubernetes service account. This allows pods running in your EKS cluster to assume the IAM role and access AWS resources securely. This integration uses OpenID Connect (OIDC) to authenticate the service account with AWS.

# Steps to Integrate Service Account with IAM Role
# 1. Create an OIDC Identity Provider:
#    - EKS clusters have an OIDC identity provider URL. You need to create an OIDC identity provider in the IAM console using this URL.
#    - This allows AWS to trust the OIDC tokens issued by your EKS cluster.
# 2. Create an IAM Role:
#    - Create an IAM role that can be assumed by the service account.
#    - The role should have a trust policy that allows the OIDC identity provider to assume the role.
# 3. Attach Policies to the IAM Role:
#    - Attach the necessary IAM policies to the role to grant the required permissions to access AWS resources.
# 4. Create a Kubernetes Service Account:
#    - Create a Kubernetes service account and annotate it with the IAM role ARN.
#    - This annotation links the service account to the IAM role.
# 5. Deploy Pods Using the Service Account:
#    - Deploy your application pods using the service account. These pods can now assume the IAM role and access AWS resources.

# eks_oidc_assume_role_policy

data "tls_certificate" "eks-certificate" {
  url = aws_eks_cluster.eks[0].identity[0].oidc[0].issuer
}

# When you create a new EKS cluster, the cluster automatically creates an OIDC identity provider in your AWS account.
# The OIDC identity provider URL is used to authenticate service accounts in your EKS cluster with AWS.
data "aws_iam_policy_document" "eks_oidc_assume_role_policy" {
  statement {
    # This action allows the openID connect provider to assume the role
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    # This condition checks if the subject (sub) claim in the OIDC token matches the specified service account identifier.
    # The test "StringEquals" ensures the variable exactly matches one of the values in the list.
    # The variable is constructed by removing "https://" from the OIDC provider URL and appending ":sub".
    # The value "system:serviceaccount:default:aws-test" is the identifier for a Kubernetes service account in the default namespace 
    # named aws-test.
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks-oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:default:aws-test"]
    }
    principals {
      identifiers = [aws_iam_openid_connect_provider.eks-oidc.arn]
      # Federated Principal: This is an external identity that AWS trusts to authenticate users. 
      # In this case, the external identity provider is an OpenID Connect (OIDC) provider.
      type        = "Federated"
    }
  }
}