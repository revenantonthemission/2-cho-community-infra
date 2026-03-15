# Master Nodes
output "master_public_ips" {
  description = "Master 노드 EIP 목록"
  value       = aws_eip.master[*].public_ip
}

output "master_private_ips" {
  description = "Master 노드 Private IP 목록"
  value       = aws_instance.master[*].private_ip
}

output "master_instance_ids" {
  description = "Master 인스턴스 ID 목록"
  value       = aws_instance.master[*].id
}

# Worker Nodes
output "worker_public_ips" {
  description = "Worker 노드 EIP 목록"
  value       = aws_eip.worker[*].public_ip
}

output "worker_private_ips" {
  description = "Worker 노드 Private IP 목록"
  value       = aws_instance.worker[*].private_ip
}

output "worker_instance_ids" {
  description = "Worker 인스턴스 ID 목록"
  value       = aws_instance.worker[*].id
}

# HAProxy
output "haproxy_public_ip" {
  description = "HAProxy EIP (HA 구성 시)"
  value       = var.haproxy_enabled ? aws_eip.haproxy[0].public_ip : null
}

output "haproxy_private_ip" {
  description = "HAProxy Private IP (HA 구성 시)"
  value       = var.haproxy_enabled ? aws_instance.haproxy[0].private_ip : null
}

# Security Groups
output "k8s_internal_sg_id" {
  description = "K8s Internal SG ID (RDS 접근 허용 등 외부 연동)"
  value       = aws_security_group.k8s_internal.id
}
