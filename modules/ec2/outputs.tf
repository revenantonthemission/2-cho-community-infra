###############################################################################
# EC2 Module - Outputs
###############################################################################

output "instance_id" {
  description = "Bastion 인스턴스 ID"
  value       = try(aws_instance.bastion[0].id, null)
}

output "public_ip" {
  description = "Bastion Elastic IP"
  value       = try(aws_eip.bastion[0].public_ip, null)
}

output "private_ip" {
  description = "Bastion 프라이빗 IP"
  value       = try(aws_instance.bastion[0].private_ip, null)
}
