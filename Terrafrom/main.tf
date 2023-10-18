terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
    backend "s3" {
    bucket         = "inviz-terraform-state-file"
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "inviz-terraform-up-and-running-locks"
    encrypt        = true
  }
}

locals {
  project_name = "inviz"
}
locals {
  cidr_block = "10.0.0.0/16"
}
locals {
  cidr_subent-1 = "10.0.1.0/24"
}
locals {
  az-1 = "ap-southeast-1a"
}
locals {
  cidr_subent-2 = "10.0.2.0/24"
}
locals {
  az-2 = "ap-southeast-1b"
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-southeast-1"
}

#  Create a VPC
resource "aws_vpc" "inviz_task_vpc" {
  cidr_block = local.cidr_block
  tags = {
    Name = "inviz "
  }
}

#  Create Subnet-1
resource "aws_subnet" "inviz_public_subnet" {
  vpc_id                  = aws_vpc.inviz_task_vpc.id
  cidr_block              = local.cidr_subent-1
  availability_zone       = local.az-1
  map_public_ip_on_launch = true

  tags = {
    Name = "publicSubnet"
  }
}

# Create subnet-2
resource "aws_subnet" "inviz_private_subnet" {
  vpc_id                  = aws_vpc.inviz_task_vpc.id
  cidr_block              = local.cidr_subent-2
  availability_zone       = local.az-2
  map_public_ip_on_launch = false

  tags = {
    Name = "privateSubnet"
  }
}

# Create internate gateway 
resource "aws_internet_gateway" "inviz-igw" {
  vpc_id = aws_vpc.inviz_task_vpc.id
  tags = {
    Name = "inviz-igw"
  }
}

# Create route table-1

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.inviz_task_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.inviz-igw.id
  }
  tags = {
    Name = "public-rt"
  }
}

# associate subnet with route table 
resource "aws_route_table_association" "public-rt_association" {
  subnet_id = aws_subnet.inviz_public_subnet.id

  route_table_id = aws_route_table.public-rt.id
}

# Create NAT Gateway

resource "aws_nat_gateway" "inviz_nat_gateway" {
  allocation_id = aws_eip.inviz_nat_eip.id
  subnet_id     = aws_subnet.inviz_public_subnet.id

  tags = {
    Name = "NatGateway"
  }
}

resource "aws_eip" "inviz_nat_eip" {
  domain   = "vpc"
}

# Create route table-2

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.inviz_task_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.inviz_nat_gateway.id
  }

  tags = {
    Name = "Private-rt"
  }
}
# associate subnet with route table 
resource "aws_route_table_association" "private-rt_association" {
  subnet_id = aws_subnet.inviz_private_subnet.id

  route_table_id = aws_route_table.private_rt.id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.3"

  cluster_name    = "eks-cluster-inviz"
  cluster_version = "1.27"

  vpc_id                         = aws_vpc.inviz_task_vpc.id
  subnet_ids                     = [aws_subnet.inviz_public_subnet.id, aws_subnet.inviz_private_subnet.id]
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }

  }
}


data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.20.0-eksbuild.1"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
}
