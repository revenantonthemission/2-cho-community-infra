# modules/k8s_ec2/iam.tf

# EC2 → ECR pull을 위한 IAM Role
resource "aws_iam_role" "k8s_node" {
  name = "${var.project}-${var.environment}-k8s-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "k8s_ecr_pull" {
  name = "${var.project}-${var.environment}-k8s-ecr-pull"
  role = aws_iam_role.k8s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "arn:aws:ecr:*:*:repository/${var.project}-*"
      }
    ]
  })
}

# S3 업로드 버킷 접근 권한 (STORAGE_BACKEND=s3일 때 사용)
resource "aws_iam_role_policy" "k8s_s3_uploads" {
  count = var.s3_uploads_bucket_arn != "" ? 1 : 0
  name  = "${var.project}-${var.environment}-k8s-s3-uploads"
  role  = aws_iam_role.k8s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${var.s3_uploads_bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.s3_uploads_bucket_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "k8s_node" {
  name = "${var.project}-${var.environment}-k8s-node"
  role = aws_iam_role.k8s_node.name

  tags = var.tags
}
