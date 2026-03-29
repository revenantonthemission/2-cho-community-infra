###############################################################################
# Staging Environment - Outputs
###############################################################################

# IAM
output "admin_user_name" {
  description = "관리자 IAM 사용자"
  value       = module.stack.admin_user_name
}

output "admin_initial_password" {
  description = "관리자 초기 비밀번호"
  value       = module.stack.admin_initial_password
  sensitive   = true
}

# VPC
output "vpc_id" {
  description = "VPC ID"
  value       = module.stack.vpc_id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = module.stack.public_subnet_ids
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = module.stack.private_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "NAT Gateway 퍼블릭 IP"
  value       = module.stack.nat_gateway_public_ips
}

# ECR
output "ecr_repository_urls" {
  description = "ECR 리포지토리 URL 맵"
  value       = module.stack.ecr_repository_urls
}

# RDS
output "rds_endpoint" {
  description = "RDS 엔드포인트"
  value       = module.stack.rds_endpoint
}

# SES
output "ses_domain_identity_arn" {
  description = "SES Domain Identity ARN"
  value       = module.stack.ses_domain_identity_arn
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
