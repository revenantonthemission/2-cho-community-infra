###############################################################################
# VPC Module - Outputs
# 다른 모듈에서 참조할 값들
###############################################################################

# VPC
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR 블록"
  value       = aws_vpc.this.cidr_block
}

# Subnets
output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 목록"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR 목록"
  value       = aws_subnet.private[*].cidr_block
}

# Availability Zones
output "availability_zones" {
  description = "사용 중인 가용 영역 목록"
  value       = local.azs
}

# Security Groups
output "rds_security_group_id" {
  description = "RDS 보안 그룹 ID"
  value       = aws_security_group.rds.id
}

# NAT Gateway EIPs (참고용)
output "nat_gateway_public_ips" {
  description = "NAT Gateway 퍼블릭 IP 목록"
  value       = aws_eip.nat[*].public_ip
}
