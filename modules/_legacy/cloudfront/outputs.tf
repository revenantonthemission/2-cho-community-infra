###############################################################################
# CloudFront Module - Outputs
###############################################################################

output "distribution_id" {
  description = "CloudFront 배포 ID (캐시 무효화용)"
  value       = aws_cloudfront_distribution.frontend.id
}

output "distribution_domain_name" {
  description = "CloudFront 도메인 (xxxx.cloudfront.net)"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "distribution_arn" {
  description = "CloudFront 배포 ARN"
  value       = aws_cloudfront_distribution.frontend.arn
}

output "custom_domain_url" {
  description = "커스텀 도메인 URL"
  value       = "https://${var.domain_name}"
}
