###############################################################################
# S3 Module - Outputs
###############################################################################

# Frontend
output "frontend_bucket_id" {
  description = "프론트엔드 S3 버킷 ID"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "프론트엔드 S3 버킷 ARN"
  value       = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_regional_domain_name" {
  description = "S3 버킷 리전별 도메인 (CloudFront OAC 오리진용)"
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
}

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
