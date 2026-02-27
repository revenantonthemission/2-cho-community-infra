###############################################################################
# Bootstrap Environment - Outputs
# 이 값들을 각 환경의 backend "s3" 블록에 리터럴로 입력
###############################################################################

output "tfstate_bucket_id" {
  description = "Terraform 상태 버킷 이름 (backend bucket에 사용)"
  value       = module.tfstate.tfstate_bucket_id
}

output "tfstate_bucket_arn" {
  description = "Terraform 상태 버킷 ARN"
  value       = module.tfstate.tfstate_bucket_arn
}

output "dynamodb_table_name" {
  description = "DynamoDB 잠금 테이블 이름 (backend dynamodb_table에 사용)"
  value       = module.tfstate.dynamodb_table_name
}

# =============================================================================
# GitHub Actions OIDC
# =============================================================================
output "oidc_provider_arn" {
  description = "GitHub Actions OIDC Provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_role_arns" {
  description = "환경별 GitHub Actions IAM 역할 ARN"
  value = {
    for env in local.environments :
    env => aws_iam_role.github_actions[env].arn
  }
}
