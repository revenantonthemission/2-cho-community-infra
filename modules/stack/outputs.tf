###############################################################################
# Stack Module - Outputs
# 환경 main.tf의 glue 리소스 및 환경 outputs.tf에서 참조하는 값
###############################################################################

# =============================================================================
# IAM
# =============================================================================
output "admin_user_name" {
  description = "관리자 IAM 사용자"
  value       = module.iam.admin_user_name
}

output "admin_initial_password" {
  description = "관리자 초기 비밀번호"
  value       = module.iam.admin_initial_password
  sensitive   = true
}

# =============================================================================
# VPC
# =============================================================================
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "NAT Gateway 퍼블릭 IP"
  value       = module.vpc.nat_gateway_public_ips
}

output "rds_security_group_id" {
  description = "RDS 보안 그룹 ID (glue SG rule용)"
  value       = module.vpc.rds_security_group_id
}

# =============================================================================
# Route53
# =============================================================================
output "zone_id" {
  description = "Route53 호스팅 영역 ID (DNS 레코드용)"
  value       = module.route53.zone_id
}

# =============================================================================
# S3
# =============================================================================
output "uploads_bucket_arn" {
  description = "업로드 S3 버킷 ARN (K8s S3 접근용)"
  value       = module.s3.uploads_bucket_arn
}

output "cloudtrail_logs_bucket_id" {
  description = "CloudTrail 로그 S3 버킷 ID"
  value       = module.s3.cloudtrail_logs_bucket_id
}

# =============================================================================
# ACM
# =============================================================================
output "certificate_arn" {
  description = "ACM 인증서 ARN"
  value       = module.acm.certificate_arn
}

# =============================================================================
# SES
# =============================================================================
output "ses_domain_identity_arn" {
  description = "SES Domain Identity ARN"
  value       = module.ses.domain_identity_arn
}

# =============================================================================
# ECR
# =============================================================================
output "ecr_repository_urls" {
  description = "ECR 리포지토리 URL 맵"
  value       = module.ecr.repository_urls
}

# =============================================================================
# RDS
# =============================================================================
output "rds_endpoint" {
  description = "RDS 엔드포인트"
  value       = module.rds.endpoint
}
