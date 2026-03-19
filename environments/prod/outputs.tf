###############################################################################
# Prod Environment - Outputs
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

# ECR
output "ecr_repository_urls" {
  description = "ECR 리포지토리 URL 맵"
  value       = module.ecr.repository_urls
}

# RDS
output "rds_endpoint" {
  description = "RDS 엔드포인트"
  value       = module.rds.endpoint
}

# SES
output "ses_domain_identity_arn" {
  description = "SES Domain Identity ARN"
  value       = module.ses.domain_identity_arn
}

# EKS Cluster
output "eks_cluster_name" {
  description = "EKS 클러스터 이름"
  value       = var.create_eks_cluster ? module.eks[0].cluster_name : null
}

output "eks_cluster_endpoint" {
  description = "EKS 클러스터 엔드포인트"
  value       = var.create_eks_cluster ? module.eks[0].cluster_endpoint : null
}

output "cluster_autoscaler_role_arn" {
  description = "Cluster Autoscaler IRSA Role ARN"
  value       = var.create_eks_cluster ? module.eks[0].cluster_autoscaler_role_arn : null
}

output "external_secrets_role_arn" {
  description = "External Secrets Operator IRSA Role ARN"
  value       = var.create_eks_cluster ? module.eks[0].external_secrets_role_arn : null
}
