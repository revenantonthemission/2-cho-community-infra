###############################################################################
# GitHub Actions OIDC Provider + Per-Environment IAM Roles
#
# AWS 계정당 1개만 존재할 수 있는 OIDC provider를 bootstrap에서 관리
# bootstrap 상태는 절대 destroy하지 않으므로 안전
#
# 사용법:
#   1. terraform apply (bootstrap 디렉토리에서 MFA 자격증명으로)
#   2. 각 repo의 GitHub Settings > Environments에 dev/staging/prod 생성
#   3. Repository variables에 AWS_ACCOUNT_ID 설정
###############################################################################

data "aws_caller_identity" "current" {}

# =============================================================================
# OIDC Provider (계정당 1개)
# =============================================================================
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub OIDC 인증서 thumbprint
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = local.common_tags
}

# =============================================================================
# Per-Environment IAM Roles (for_each로 3개 환경 일괄 생성)
# =============================================================================

locals {
  environments = ["dev", "staging", "prod"]

  # 환경별 허용할 OIDC subject 목록
  # dev/staging: fork repo에서 배포 허용
  # prod: upstream(원본) repo에서만 배포 허용
  github_actions_subjects = {
    dev = [
      "repo:${var.github_fork_owner}/2-cho-community-be:environment:dev",
      "repo:${var.github_fork_owner}/2-cho-community-fe:environment:dev",
      "repo:${var.github_fork_owner}/2-cho-community-infra:environment:dev",
      "repo:${var.github_upstream_owner}/2-cho-community-infra:environment:dev",
    ]
    staging = [
      "repo:${var.github_fork_owner}/2-cho-community-be:environment:staging",
      "repo:${var.github_fork_owner}/2-cho-community-fe:environment:staging",
      "repo:${var.github_fork_owner}/2-cho-community-infra:environment:staging",
      "repo:${var.github_upstream_owner}/2-cho-community-infra:environment:staging",
    ]
    prod = [
      "repo:${var.github_upstream_owner}/2-cho-community-be:environment:prod",
      "repo:${var.github_upstream_owner}/2-cho-community-fe:environment:prod",
      "repo:${var.github_upstream_owner}/2-cho-community-infra:environment:prod",
    ]
  }
}

resource "aws_iam_role" "github_actions" {
  for_each = toset(local.environments)

  name = "${var.project}-${each.key}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_actions_subjects[each.key]
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Environment = each.key
    Purpose     = "GitHub Actions OIDC"
  })
}

# =============================================================================
# IAM Policies — 배포 권한 (ECR + Lambda + S3 + CloudFront)
# =============================================================================
resource "aws_iam_role_policy" "github_actions_deploy" {
  for_each = toset(local.environments)

  name = "deploy-policy"
  role = aws_iam_role.github_actions[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project}-${each.key}-*"
      },
      {
        Sid    = "LambdaUpdate"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:GetFunction"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project}-${each.key}-*"
      },
      {
        Sid    = "S3Deploy"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-${each.key}-frontend",
          "arn:aws:s3:::${var.project}-${each.key}-frontend/*"
        ]
      },
      {
        Sid    = "CloudFrontInvalidation"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation"
        ]
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"
      }
    ]
  })
}

# =============================================================================
# IAM Policies — Terraform 권한 (상태 접근 + 인프라 관리)
# =============================================================================
resource "aws_iam_role_policy" "github_actions_terraform" {
  for_each = toset(local.environments)

  name = "terraform-policy"
  role = aws_iam_role.github_actions[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-tfstate",
          "arn:aws:s3:::${var.project}-tfstate/${each.key}/*"
        ]
      },
      {
        Sid    = "TerraformStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/terraform-locks"
      }
    ]
  })
}

# Terraform apply에 필요한 광범위 권한
# 인프라 리소스 생성/삭제를 위해 AdministratorAccess 부여
# GitHub Environment 보호 규칙 + OIDC subject 스코핑으로 위험 최소화
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  for_each = toset(local.environments)

  role       = aws_iam_role.github_actions[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
