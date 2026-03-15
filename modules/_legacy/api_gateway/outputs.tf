###############################################################################
# API Gateway Module - Outputs
###############################################################################

output "api_id" {
  description = "API Gateway ID"
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "API Gateway 기본 엔드포인트"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "custom_domain_url" {
  description = "커스텀 도메인 URL"
  value       = "https://${var.api_domain_name}"
}

output "execution_arn" {
  description = "API Gateway 실행 ARN"
  value       = aws_apigatewayv2_api.this.execution_arn
}
