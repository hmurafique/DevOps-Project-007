# EKS Cluster IAM Role
resource "aws_iam_role" "eks-cluster-role" {
  name = "EKS_CLOUD_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks-cluster-policy" {
  role       = aws_iam_role.eks-cluster-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS Node Group IAM Role
resource "aws_iam_role" "eks-node-role" {
  name = "EKS_CLOUD_Node_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks-worker-node-policy" {
  role       = aws_iam_role.eks-node-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks-cni-policy" {
  role       = aws_iam_role.eks-node-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks-ecr-policy" {
  role       = aws_iam_role.eks-node-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EKS Cluster
resource "aws_eks_cluster" "mario-eks" {
  name     = "EKS_CLOUD"
  role_arn = aws_iam_role.eks-cluster-role.arn

  vpc_config {
    subnet_ids = [
      "subnet-0415d174ef2ef72b2",
      "subnet-021637e5ab2d40ee1",
      "subnet-0adfb34eba7952108"
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-cluster-policy
  ]
}

# EKS Node Group
resource "aws_eks_node_group" "mario-nodes" {
  cluster_name    = aws_eks_cluster.mario-eks.name
  node_group_name = "mario-node-group"
  node_role_arn   = aws_iam_role.eks-node-role.arn
  subnet_ids      = [
    "subnet-0415d174ef2ef72b2",
    "subnet-021637e5ab2d40ee1",
    "subnet-0adfb34eba7952108"
  ]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks-worker-node-policy,
    aws_iam_role_policy_attachment.eks-cni-policy,
    aws_iam_role_policy_attachment.eks-ecr-policy
  ]
}
