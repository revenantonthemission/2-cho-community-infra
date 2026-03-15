###############################################################################
# EFS Module - Outputs
###############################################################################

output "file_system_id" {
  description = "EFS 파일 시스템 ID"
  value       = aws_efs_file_system.this.id
}

output "file_system_arn" {
  description = "EFS 파일 시스템 ARN"
  value       = aws_efs_file_system.this.arn
}

output "access_point_id" {
  description = "Lambda용 EFS 액세스 포인트 ID"
  value       = aws_efs_access_point.lambda.id
}

output "access_point_arn" {
  description = "Lambda용 EFS 액세스 포인트 ARN"
  value       = aws_efs_access_point.lambda.arn
}
