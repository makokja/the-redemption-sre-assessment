# EKS cluster module for high availability setup

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# IAM role for EKS cluster
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# Security group for cluster control plane
resource "aws_security_group" "cluster" {
  name = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id = var.vpc_id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-sg"
    }
  )
}

# KMS encryption key for secrets
resource "aws_kms_key" "eks" {
  description = "EKS Secret Encryption Key for ${var.cluster_name}"
  deletion_window_in_days = 10
  enable_key_rotation = true

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-eks-key"
    }
  )
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# Main EKS cluster resource
resource "aws_eks_cluster" "main" {
  name = var.cluster_name
  version = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access = true
    public_access_cidrs = var.cluster_endpoint_public_access_cidrs
    security_group_ids = [aws_security_group.cluster.id]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = var.cluster_enabled_log_types

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.cluster
  ]

  tags = var.tags
}

# CloudWatch logs for control plane
resource "aws_cloudwatch_log_group" "cluster" {
  name = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7

  tags = var.tags
}

# OIDC provider for service account IAM roles
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  count = var.enable_irsa ? 1 : 0

  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}

# Node IAM Role
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node.name
}

# Security group for worker nodes
resource "aws_security_group" "node" {
  name = "${var.cluster_name}-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id = var.vpc_id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.cluster_name}-node-sg"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )
}

# Allow nodes to communicate with each other
resource "aws_security_group_rule" "node_ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  security_group_id = aws_security_group.node.id
  source_security_group_id = aws_security_group.node.id
  description       = "Allow nodes to communicate with each other"
}

# Allow nodes to receive communication from cluster control plane
resource "aws_security_group_rule" "node_ingress_cluster" {
  type              = "ingress"
  from_port         = 1025
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
  description       = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
}

# Allow cluster control plane to communicate with nodes
resource "aws_security_group_rule" "cluster_ingress_node_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
  description       = "Allow pods to communicate with the cluster API Server"
}

# Node groups for the cluster
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn = aws_iam_role.node.arn
  subnet_ids = var.subnet_ids
  version = var.cluster_version

  scaling_config {
    desired_size = each.value.desired_capacity
    max_size = each.value.max_capacity
    min_size = each.value.min_capacity
  }

  update_config {
    max_unavailable_percentage = 33
  }

  instance_types = each.value.instance_types
  capacity_type = each.value.capacity_type

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key = taint.value.key
      value = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${each.key}"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]
  }
}

# Install cluster addons
resource "aws_eks_addon" "main" {
  for_each = var.cluster_addons

  cluster_name = aws_eks_cluster.main.name
  addon_name = each.key
  addon_version = try(each.value.addon_version, null)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}
