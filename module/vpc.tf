# Define a local value 'cluster-name' as a shorthand reference to 'var.cluster-name' 
# for improved readability and maintainability.
# Define local values for the Terraform configuration.
# The 'cluster-name' local value is set to the value of the 'cluster-name' variable.
locals {
  cluster-name = var.cluster-name
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr-block
  instance_tenancy     = "default"
  # Required for EKS. This will enable DNS resolution for the VPC.
  enable_dns_hostnames = true

  # Required for EKS. This will enable DNS support for the VPC.
  enable_dns_support   = true

  # Tagging kubernetes.io/cluster is usually for resources like subnets and IGWs to associate them with a Kubernetes cluster.
  # The VPC itself doesn't need this tag as it is a broader network container.
  tags = {
    Name = var.vpc-name
    Env  = var.env

  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name                                          = var.igw-name
    env                                           = var.env

    # Tag to associate the VPC with the Kubernetes cluster.
    # This tag is required for the Kubernetes cluster to recognize and manage resources within the VPC.
    # The value "owned" indicates that the cluster owns the VPC.
    # This tag is used to associate AWS resources with a specific Kubernetes cluster.
    # The "kubernetes.io/cluster/${local.cluster-name}" tag is typically used by Kubernetes
    # to identify resources that belong to a particular cluster. The value "owned" indicates
    # that the resource is owned by the cluster. This tag is not mandatory for an internet gateway,
    # but it is useful for resource management and organization within a Kubernetes cluster.
    "kubernetes.io/cluster/${local.cluster-name}" = "owned"
  }

  depends_on = [aws_vpc.vpc]
}

resource "aws_subnet" "public-subnet" {
  # This will iterate over the number of public subnets defined in the variable `var.pub-subnet-count`.
  count                   = var.pub-subnet-count
  vpc_id                  = aws_vpc.vpc.id
  
  # Assigns a CIDR block to the VPC from the list of public CIDR blocks defined 
  # in the variable `var.pub-cidr-block`.
  # The specific CIDR block is selected based on the current index of the resource being created.
  cidr_block              = element(var.pub-cidr-block, count.index)
  availability_zone       = element(var.pub-availability-zone, count.index)

  #Required for EKS. If Instance (worker node) launched in public subnet will have public IP.
  #We will also use this subnet for ELB.
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${var.pub-sub-name}-${count.index + 1}"
    Env                                           = var.env
    
    # This tag is used to associate the VPC with the EKS cluster.
    # The value "owned" indicates that the VPC is exclusively owned by the EKS cluster.
    # If the value were "shared", it would indicate that the VPC is shared among multiple clusters or resources.
    # Note: When deleting the EKS cluster, resources with the "owned" tag will be deleted automatically.
    # Resources with the "shared" tag will not be deleted automatically.
    # Mandatory for EKS. This tag is mandatory for associating the subnet with the EKS cluster.
    "kubernetes.io/cluster/${local.cluster-name}" = "owned"

    # Mandatory for EKS. This tag will allow the public subnet to be used by the ELB.
    # when loadbalncer service is created, EKS will look for this tag to identify the subnet.
    "kubernetes.io/role/elb"                      = "1"
  }

  depends_on = [aws_vpc.vpc,]
}

resource "aws_subnet" "private-subnet" {
  count                   = var.pri-subnet-count
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = element(var.pri-cidr-block, count.index)
  availability_zone       = element(var.pri-availability-zone, count.index)
  # we donot need public IP for worker nodes.
  map_public_ip_on_launch = false

  tags = {
    Name                                          = "${var.pri-sub-name}-${count.index + 1}"
    Env                                           = var.env
    # This tag means that this subnet would be used only by the specific EKS cluster for internal ELB.
    # If shared is provided, it means that this subnet can be used by multiple EKS clusters.
    "kubernetes.io/cluster/${local.cluster-name}" = "owned"
    # note the use of "internal-elb" instead of "elb" for private subnets
    "kubernetes.io/role/internal-elb"             = "1"
  }

  depends_on = [aws_vpc.vpc]
}

# The public route table is associated with the internet gateway to allow the public subnet to access the internet.
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = var.public-rt-name
    env  = var.env
  }

  depends_on = [aws_vpc.vpc]
}

# Associate the public route table with all 3 public subnet.
resource "aws_route_table_association" "name" {
  count          = 3
  route_table_id = aws_route_table.public-rt.id
  subnet_id      = aws_subnet.public-subnet[count.index].id

  depends_on = [aws_vpc.vpc,
    aws_subnet.public-subnet
  ]
}
// NAT Gateway needs elastic IP to be associated with it so that  it can be accessed from internet.
resource "aws_eip" "ngw-eip" {
  # The 'domain' attribute specifies the scope in which the Elastic IP (EIP) will be used.
  # Possible values are "vpc" for VPC-specific EIPs and "standard" for standard EIPs.
  # In this case, "vpc" indicates that the EIP will be associated with a VPC resource.
  # standard indicates that the EIP will be associated with an EC2 instance.
  domain = "vpc"

  tags = {
    Name = var.eip-name
  }

  # Elastic IP (EIP) can only be created after the VPC is created. 
  # This is because an EIP needs to be associated with a network interface, 
  # which in turn is associated with a subnet within a VPC. 
  depends_on = [aws_vpc.vpc]

}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.ngw-eip.id
  # we are allowing only one subnet to use this NAT Gateway.
  # which means the oher private subnet will also use this NAT Gateway to access internet.
  # This is made possible by route table rules.
  subnet_id     = aws_subnet.public-subnet[0].id

  tags = {
    Name = var.ngw-name
  }

  depends_on = [aws_vpc.vpc,
    aws_eip.ngw-eip
  ]
}

# The private route table internet traffic is associated with the NAT Gateway to allow the private subnet to access the internet.
# Note: The traffic within the VPC is inherited by default by the default/main route rule which needs no additional configuration.
resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }

  tags = {
    Name = var.private-rt-name
    env  = var.env
  }

  depends_on = [aws_vpc.vpc]
}

# Associate the private route table with all 3 private subnet.
resource "aws_route_table_association" "private-rt-association" {
  count          = 3
  route_table_id = aws_route_table.private-rt.id
  subnet_id      = aws_subnet.private-subnet[count.index].id

  depends_on = [aws_vpc.vpc,
    aws_subnet.private-subnet
  ]
}

resource "aws_security_group" "eks-cluster-sg" {
  name        = var.eks-sg
  description = "Allow 443 from Jump Server only"

  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // It should be specific IP range
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.eks-sg
  }
}