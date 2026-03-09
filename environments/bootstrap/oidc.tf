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
  # dev/staging: fork + upstream 모두 배포 허용
  # prod: upstream(원본) repo에서만 배포 허용
  github_actions_subjects = {
    dev = [
      "repo:${var.github_fork_owner}/2-cho-community-be:environment:dev",
      "repo:${var.github_fork_owner}/2-cho-community-fe:environment:dev",
      "repo:${var.github_fork_owner}/2-cho-community-infra:environment:dev",
      "repo:${var.github_upstream_owner}/2-cho-community-be:environment:dev",
      "repo:${var.github_upstream_owner}/2-cho-community-fe:environment:dev",
      "repo:${var.github_upstream_owner}/2-cho-community-infra:environment:dev",
    ]
    staging = [
      "repo:${var.github_fork_owner}/2-cho-community-be:environment:staging",
      "repo:${var.github_fork_owner}/2-cho-community-fe:environment:staging",
      "repo:${var.github_fork_owner}/2-cho-community-infra:environment:staging",
      "repo:${var.github_upstream_owner}/2-cho-community-be:environment:staging",
      "repo:${var.github_upstream_owner}/2-cho-community-fe:environment:staging",
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
          "lambda:GetFunction",
          "lambda:PublishVersion",
          "lambda:GetAlias",
          "lambda:CreateAlias",
          "lambda:UpdateAlias",
          "lambda:InvokeFunction"
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

# Terraform apply에 필요한 인프라 관리 권한 (최소 권한 원칙)
# AdministratorAccess 대신 프로젝트에서 사용하는 서비스만 허용
# GitHub Environment 보호 규칙 + OIDC subject 스코핑으로 추가 보호
resource "aws_iam_role_policy" "github_actions_infra" {
  for_each = toset(local.environments)

  name = "infra-management-policy"
  role = aws_iam_role.github_actions[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPCAndNetworking"
        Effect = "Allow"
        Action = [
          "ec2:*Vpc*", "ec2:*Subnet*", "ec2:*RouteTable*", "ec2:*Route",
          "ec2:*InternetGateway*", "ec2:*NatGateway*", "ec2:*SecurityGroup*",
          "ec2:*NetworkAcl*", "ec2:*Address*", "ec2:*KeyPair*",
          "ec2:*Instance*", "ec2:*Volume*", "ec2:*Tags*",
          "ec2:*FlowLog*", "ec2:*NetworkInterface*",
          "ec2:Describe*", "ec2:CreateTags", "ec2:DeleteTags",
          "ec2:RunInstances", "ec2:TerminateInstances",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
          "ec2:AllocateAddress", "ec2:ReleaseAddress",
          "ec2:AssociateAddress", "ec2:DisassociateAddress"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Management"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket", "s3:DeleteBucket", "s3:ListBucket",
          "s3:GetBucket*", "s3:PutBucket*", "s3:DeleteBucket*",
          "s3:GetObject*", "s3:PutObject*", "s3:DeleteObject*",
          "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration",
          "s3:GetLifecycleConfiguration", "s3:PutLifecycleConfiguration",
          "s3:GetAccelerateConfiguration", "s3:GetAnalyticsConfiguration",
          "s3:GetInventoryConfiguration", "s3:GetMetricsConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      },
      {
        Sid    = "RDSManagement"
        Effect = "Allow"
        Action = [
          "rds:*"
        ]
        Resource = "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "RDSDescribe"
        Effect = "Allow"
        Action = [
          "rds:Describe*", "rds:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaManagement"
        Effect = "Allow"
        Action = [
          "lambda:*"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project}-*"
      },
      {
        Sid    = "LambdaGlobal"
        Effect = "Allow"
        Action = [
          "lambda:ListFunctions", "lambda:GetAccountSettings",
          "lambda:ListEventSourceMappings"
        ]
        Resource = "*"
      },
      {
        Sid    = "APIGateway"
        Effect = "Allow"
        Action = [
          "apigateway:*"
        ]
        Resource = [
          "arn:aws:apigateway:${var.aws_region}::*"
        ]
      },
      {
        Sid    = "CloudFrontManagement"
        Effect = "Allow"
        Action = [
          "cloudfront:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRManagement"
        Effect = "Allow"
        Action = [
          "ecr:*"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project}-*"
      },
      {
        Sid    = "ECRGlobal"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken", "ecr:DescribeRepositories"
        ]
        Resource = "*"
      },
      {
        Sid    = "EFSManagement"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:*"
        ]
        Resource = "*"
      },
      {
        # 프로젝트 리소스에 한정된 IAM 관리 (권한 상승 방지)
        Sid    = "IAMRolesAndPolicies"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole",
          "iam:PassRole", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
          "iam:GetRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies", "iam:ListInstanceProfilesForRole",
          "iam:GetUser", "iam:CreateUser", "iam:DeleteUser", "iam:UpdateUser",
          "iam:TagUser", "iam:UntagUser", "iam:ListUserTags", "iam:ListGroupsForUser",
          "iam:GetLoginProfile", "iam:CreateLoginProfile", "iam:DeleteLoginProfile",
          "iam:GetGroup", "iam:CreateGroup", "iam:DeleteGroup",
          "iam:AddUserToGroup", "iam:RemoveUserFromGroup",
          "iam:GetGroupPolicy", "iam:PutGroupPolicy", "iam:DeleteGroupPolicy",
          "iam:AttachGroupPolicy", "iam:DetachGroupPolicy",
          "iam:ListAttachedGroupPolicies", "iam:ListGroupPolicies",
          "iam:GetInstanceProfile", "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile", "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${var.project}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/admin-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:group/${var.project}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project}-*"
        ]
      },
      {
        # IAM 정책 관리 (프로젝트 범위로 제한 — 권한 상승 방지)
        Sid    = "IAMPolicies"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy", "iam:CreatePolicy", "iam:DeletePolicy",
          "iam:GetPolicyVersion", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project}-*"
        ]
      },
      {
        # IAM 글로벌 읽기 + 서비스 연결 역할 생성
        Sid    = "IAMGlobalAndServiceLinkedRole"
        Effect = "Allow"
        Action = [
          "iam:ListInstanceProfiles",
          "iam:CreateServiceLinkedRole",
          "iam:GetAccountPasswordPolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53Management"
        Effect = "Allow"
        Action = [
          "route53:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ACMManagement"
        Effect = "Allow"
        Action = [
          "acm:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchAndLogs"
        Effect = "Allow"
        Action = [
          "cloudwatch:*",
          "logs:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudTrailManagement"
        Effect = "Allow"
        Action = [
          "cloudtrail:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMParameterStore"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter*", "ssm:PutParameter", "ssm:DeleteParameter*",
          "ssm:DescribeParameters", "ssm:ListTagsForResource",
          "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDBStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem",
          "dynamodb:DescribeTable", "dynamodb:CreateTable",
          "dynamodb:ListTables", "dynamodb:ListTagsOfResource",
          "dynamodb:TagResource", "dynamodb:UntagResource",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTimeToLive", "dynamodb:UpdateTimeToLive"
        ]
        Resource = "*"
      },
      {
        Sid    = "EventBridgeManagement"
        Effect = "Allow"
        Action = [
          "events:PutRule", "events:DeleteRule", "events:DescribeRule",
          "events:EnableRule", "events:DisableRule", "events:ListRules",
          "events:PutTargets", "events:RemoveTargets", "events:ListTargets*",
          "events:ListTagsForResource", "events:TagResource", "events:UntagResource",
          "events:CreateConnection", "events:DeleteConnection",
          "events:DescribeConnection", "events:UpdateConnection",
          "events:CreateApiDestination", "events:DeleteApiDestination",
          "events:DescribeApiDestination", "events:UpdateApiDestination"
        ]
        Resource = [
          "arn:aws:events:*:${data.aws_caller_identity.current.account_id}:rule/${var.project}-*",
          "arn:aws:events:*:${data.aws_caller_identity.current.account_id}:connection/${var.project}-*",
          "arn:aws:events:*:${data.aws_caller_identity.current.account_id}:api-destination/${var.project}-*"
        ]
      },
      {
        Sid    = "EventBridgeSecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:CreateSecret",
          "secretsmanager:UpdateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:PutSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:events!connection/${var.project}-*"
      },
      {
        Sid    = "KMSForEncryption"
        Effect = "Allow"
        Action = [
          "kms:CreateKey", "kms:DescribeKey", "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus", "kms:ListResourceTags",
          "kms:ScheduleKeyDeletion", "kms:TagResource", "kms:UntagResource",
          "kms:CreateAlias", "kms:DeleteAlias", "kms:ListAliases",
          "kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "STSForTerraform"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}
