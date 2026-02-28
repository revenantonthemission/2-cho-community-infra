###############################################################################
# IAM Module
# 사용자, 그룹, 정책 관리 (루트 계정 대체)
###############################################################################

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Admin Group (관리자 그룹)
# -----------------------------------------------------------------------------
resource "aws_iam_group" "admin" {
  name = "${var.project}-${var.environment}-admin"
}

resource "aws_iam_group_policy_attachment" "admin" {
  group      = aws_iam_group.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# MFA 강제 정책: MFA 없이는 IAM 외 서비스 접근 불가
resource "aws_iam_group_policy" "require_mfa" {
  name  = "require-mfa"
  group = aws_iam_group.admin.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowViewAccountInfo"
        Effect = "Allow"
        Action = [
          "iam:GetAccountPasswordPolicy",
          "iam:ListVirtualMFADevices"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowManageOwnMFA"
        Effect = "Allow"
        Action = [
          "iam:CreateVirtualMFADevice",
          "iam:DeleteVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:ListMFADevices",
          "iam:ResyncMFADevice",
          "iam:DeactivateMFADevice"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:mfa/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/$${aws:username}"
        ]
      },
      {
        Sid    = "AllowManageOwnPasswords"
        Effect = "Allow"
        Action = [
          "iam:ChangePassword",
          "iam:GetUser"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/$${aws:username}"
      },
      {
        Sid    = "DenyAllExceptListedIfNoMFA"
        Effect = "Deny"
        NotAction = [
          "iam:CreateVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:GetUser",
          "iam:ListMFADevices",
          "iam:ListVirtualMFADevices",
          "iam:ResyncMFADevice",
          "iam:ChangePassword",
          "sts:GetSessionToken"
        ]
        Resource = "*"
        Condition = {
          BoolIfExists = {
            "aws:MultiFactorAuthPresent" = "false"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Admin User (루트 계정 대체)
# -----------------------------------------------------------------------------
resource "aws_iam_user" "admin" {
  count = var.admin_username != "" ? 1 : 0

  name          = var.admin_username
  force_destroy = false

  tags = merge(var.tags, {
    Name = var.admin_username
    Role = "admin"
  })
}

resource "aws_iam_user_group_membership" "admin" {
  count = var.admin_username != "" ? 1 : 0

  user   = aws_iam_user.admin[0].name
  groups = [aws_iam_group.admin.name]
}

# 콘솔 로그인 프로필 (초기 비밀번호 변경 필수)
resource "aws_iam_user_login_profile" "admin" {
  count = var.admin_username != "" ? 1 : 0

  user                    = aws_iam_user.admin[0].name
  password_reset_required = true
}

# -----------------------------------------------------------------------------
# Developer Group (개발자 그룹 — 제한된 권한)
# -----------------------------------------------------------------------------
resource "aws_iam_group" "developer" {
  name = "${var.project}-${var.environment}-developer"
}

# 개발자: 읽기 전용 + Lambda/S3/ECR 배포 권한
resource "aws_iam_policy" "developer" {
  name = "${var.project}-${var.environment}-developer-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnlyAccess"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "rds:Describe*",
          "efs:Describe*",
          "lambda:Get*",
          "lambda:List*",
          "s3:Get*",
          "s3:List*",
          "logs:Get*",
          "logs:Describe*",
          "logs:FilterLogEvents",
          "cloudwatch:Get*",
          "cloudwatch:List*",
          "cloudwatch:Describe*",
          "apigateway:GET",
          "ecr:Describe*",
          "ecr:List*",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      },
      {
        Sid    = "DeployLambda"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:PublishVersion"
        ]
        Resource = "arn:aws:lambda:*:${data.aws_caller_identity.current.account_id}:function:${var.project}-*"
      },
      {
        Sid    = "PushECR"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Sid    = "DeployFrontend"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.project}-*-frontend/*"
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "developer" {
  group      = aws_iam_group.developer.name
  policy_arn = aws_iam_policy.developer.arn
}

# -----------------------------------------------------------------------------
# Terraform Deployer Role (CI/CD에서 assume하여 인프라 관리)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "terraform_deployer" {
  count = var.create_deployer_role ? 1 : 0

  name = "${var.project}-${var.environment}-terraform-deployer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# PowerUserAccess: IAM 관리 제외 전체 서비스 접근 (AdministratorAccess 대체)
# IAM 권한은 bootstrap OIDC 역할에서 프로젝트 범위로 제한하여 관리
resource "aws_iam_role_policy_attachment" "terraform_deployer" {
  count = var.create_deployer_role ? 1 : 0

  role       = aws_iam_role.terraform_deployer[0].name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# -----------------------------------------------------------------------------
# Password Policy (계정 전체 비밀번호 정책)
# -----------------------------------------------------------------------------
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 12
}
