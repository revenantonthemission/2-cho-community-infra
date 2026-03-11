# modules/ses/outputs.tf

output "domain_identity_arn" {
  description = "SES Domain Identity ARN (IAM 정책에서 참조)"
  value       = aws_ses_domain_identity.this.arn
}

output "domain_name" {
  description = "SES에 등록된 도메인"
  value       = aws_ses_domain_identity.this.domain
}
