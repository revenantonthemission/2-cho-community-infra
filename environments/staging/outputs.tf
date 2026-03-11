###############################################################################
# Dev Environment - Outputs
###############################################################################

# IAM
output "admin_user_name" {
  description = "관리자 IAM 사용자"
  value       = module.iam.admin_user_name
}

output "admin_initial_password" {
  description = "관리자 초기 비밀번호"
  value       = module.iam.admin_initial_password
  sensitive   = true
}

# VPC
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

# S3
output "frontend_bucket_domain" {
  description = "S3 프론트엔드 버킷 도메인 (CloudFront OAC 오리진)"
  value       = module.s3.frontend_bucket_regional_domain_name
}

# ECR
output "ecr_repository_url" {
  description = "ECR 레포지토리 URL"
  value       = module.ecr.repository_url
}

# RDS
output "rds_endpoint" {
  description = "RDS 엔드포인트"
  value       = module.rds.endpoint
}

# Lambda
output "lambda_function_name" {
  description = "Lambda 함수 이름"
  value       = module.lambda.function_name
}

# API Gateway
output "api_gateway_endpoint" {
  description = "API Gateway 엔드포인트"
  value       = module.api_gateway.api_endpoint
}

output "api_custom_domain_url" {
  description = "API 커스텀 도메인 URL"
  value       = module.api_gateway.custom_domain_url
}

# EC2 (Bastion)
output "bastion_public_ip" {
  description = "Bastion Elastic IP"
  value       = module.ec2.public_ip
}

# CloudWatch
output "dashboard_name" {
  description = "CloudWatch 대시보드"
  value       = module.cloudwatch.dashboard_name
}

# SES
output "ses_domain_identity_arn" {
  description = "SES Domain Identity ARN"
  value       = module.ses.domain_identity_arn
}

# CloudFront
output "cloudfront_domain" {
  description = "CloudFront 도메인"
  value       = module.cloudfront.distribution_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront 배포 ID (캐시 무효화용)"
  value       = module.cloudfront.distribution_id
}

output "frontend_url" {
  description = "프론트엔드 URL (CloudFront + 커스텀 도메인)"
  value       = module.cloudfront.custom_domain_url
}
