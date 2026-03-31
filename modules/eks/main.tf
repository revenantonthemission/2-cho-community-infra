###############################################################################
# EKS 클러스터 모듈
# - Managed Node Group (t3.medium)
# - IRSA (S3 업로드용)
# - EKS → RDS 접근 SG
###############################################################################

data "aws_caller_identity" "current" {}

# =============================================================================
# EKS Cluster
# =============================================================================
resource "aws_eks_cluster" "this" {
  name     = "${var.project}-${var.environment}"
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = [aws_security_group.cluster.id]
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
  ]
}

# =============================================================================
# EKS Cluster IAM Role
# =============================================================================
resource "aws_iam_role" "cluster" {
  name = "${var.project}-${var.environment}-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# =============================================================================
# Managed Node Group
# =============================================================================
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-${var.environment}-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# =============================================================================
# Node Group IAM Role
# =============================================================================
resource "aws_iam_role" "node" {
  name = "${var.project}-${var.environment}-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# S3 업로드 접근 (노드 역할에 직접 부여)
resource "aws_iam_role_policy" "node_s3_uploads" {
  count = var.enable_s3_uploads ? 1 : 0

  name = "s3-uploads"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"
      ]
      Resource = [
        var.s3_uploads_bucket_arn,
        "${var.s3_uploads_bucket_arn}/*"
      ]
    }]
  })
}

# =============================================================================
# Security Groups
# =============================================================================
resource "aws_security_group" "cluster" {
  name_prefix = "${var.project}-${var.environment}-eks-cluster-"
  description = "EKS cluster security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-eks-cluster"
  })
}

# 노드 → RDS 접근 허용을 위한 SG 출력
# (main.tf에서 aws_security_group_rule로 RDS SG에 추가)

# =============================================================================
# OIDC Provider (IRSA 지원)
# =============================================================================
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = var.tags
}

# =============================================================================
# Cluster Autoscaler IRSA
# Pod가 ASG 스케일링을 직접 수행하려면 IAM 권한이 필요
# =============================================================================
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${var.project}-${var.environment}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "cluster-autoscaler"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
        ]
        # EKS managed node group ASG만 조작 허용
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/eks:cluster-name" = aws_eks_cluster.this.name
          }
        }
      },
    ]
  })
}

# =============================================================================
# External Secrets Operator IRSA
# K8s ExternalSecret CRD가 Secrets Manager에서 시크릿을 읽어오기 위한 권한
# =============================================================================
resource "aws_iam_role" "external_secrets" {
  name = "${var.project}-${var.environment}-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:app:external-secrets"
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

# =============================================================================
# App API IRSA (S3 업로드 + SES 이메일 발송)
# EKS Pod는 IMDS 접근이 차단되므로 IRSA로 AWS 권한 부여
# =============================================================================
resource "aws_iam_role" "app_api" {
  name = "${var.project}-${var.environment}-app-s3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:app:community-api"
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "app_s3_uploads" {
  count = var.enable_s3_uploads ? 1 : 0
  name  = "s3-uploads"
  role  = aws_iam_role.app_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        var.s3_uploads_bucket_arn,
        "${var.s3_uploads_bucket_arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "app_ses_send" {
  name = "ses-send"
  role = aws_iam_role.app_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "ses:FromAddress" = "noreply@${var.domain_name}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "secrets-manager-read"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}-${var.environment}-*"
    }]
  })
}

# =============================================================================
# CloudWatch Exporter IRSA
# RDS CloudWatch 메트릭을 Prometheus로 수집하기 위한 읽기 전용 권한
# =============================================================================
resource "aws_iam_role" "cloudwatch_exporter" {
  name = "${var.project}-${var.environment}-cloudwatch-exporter"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:monitoring:prometheus-cloudwatch-exporter"
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cloudwatch_exporter" {
  name = "cloudwatch-readonly"
  role = aws_iam_role.cloudwatch_exporter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
      ]
      Resource = "*"
    }]
  })
}
