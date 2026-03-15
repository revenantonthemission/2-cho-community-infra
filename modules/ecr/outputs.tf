###############################################################################
# ECR Module - Outputs
###############################################################################

output "repository_urls" {
  description = "ECR 리포지토리 URL 맵 (name → URL)"
  value       = { for k, v in aws_ecr_repository.additional : k => v.repository_url }
}

output "repository_arns" {
  description = "ECR 리포지토리 ARN 맵 (name → ARN)"
  value       = { for k, v in aws_ecr_repository.additional : k => v.arn }
}

output "repository_names" {
  description = "ECR 리포지토리 이름 리스트"
  value       = [for v in aws_ecr_repository.additional : v.name]
}
