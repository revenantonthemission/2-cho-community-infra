###############################################################################
# S3 Module - Outputs
###############################################################################

# CloudTrail Logs
output "cloudtrail_logs_bucket_id" {
  description = "CloudTrail 로그 버킷 ID"
  value       = aws_s3_bucket.cloudtrail_logs.id
}

output "cloudtrail_logs_bucket_arn" {
  description = "CloudTrail 로그 버킷 ARN"
  value       = aws_s3_bucket.cloudtrail_logs.arn
}

# Uploads
output "uploads_bucket_id" {
  description = "업로드 S3 버킷 ID"
  value       = var.create_uploads_bucket ? aws_s3_bucket.uploads[0].id : null
}

output "uploads_bucket_arn" {
  description = "업로드 S3 버킷 ARN"
  value       = var.create_uploads_bucket ? aws_s3_bucket.uploads[0].arn : null
}

output "uploads_bucket_regional_domain_name" {
  description = "업로드 S3 버킷 리전별 도메인"
  value       = var.create_uploads_bucket ? aws_s3_bucket.uploads[0].bucket_regional_domain_name : null
}
