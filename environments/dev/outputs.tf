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
  description = "S3 프론트엔드 버킷 도메인 (레거시 — CloudFront 제거됨)"
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

# EC2 (Bastion)
output "bastion_public_ip" {
  description = "Bastion Elastic IP"
  value       = module.ec2.public_ip
}

# SES
output "ses_domain_identity_arn" {
  description = "SES Domain Identity ARN"
  value       = module.ses.domain_identity_arn
}

# K8s Cluster
output "k8s_master_public_ips" {
  description = "K8s Master EIP 목록"
  value       = var.create_k8s_cluster ? module.k8s_ec2[0].master_public_ips : []
}

output "k8s_worker_public_ips" {
  description = "K8s Worker Public IP 목록"
  value       = var.create_k8s_cluster ? module.k8s_ec2[0].worker_public_ips : []
}

output "k8s_haproxy_public_ip" {
  description = "K8s HAProxy EIP"
  value       = var.create_k8s_cluster ? module.k8s_ec2[0].haproxy_public_ip : null
}
