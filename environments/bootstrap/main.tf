###############################################################################
# Bootstrap Environment - Main Configuration
# S3 + DynamoDB 원격 상태 백엔드 리소스를 생성하는 1회성 구성
# 부트스트랩 자체는 로컬 상태를 영구적으로 사용 (chicken-and-egg 문제 회피)
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# Module: Terraform Remote State Backend (S3 + DynamoDB)
# =============================================================================
module "tfstate" {
  source = "../../modules/tfstate"

  project     = var.project
  environment = var.environment
  account_id  = var.account_id

  github_actions_role_arns = [
    "arn:aws:iam::${var.account_id}:role/${var.project}-staging-github-actions",
    "arn:aws:iam::${var.account_id}:role/${var.project}-prod-github-actions"
  ]

  tags = local.common_tags
}
