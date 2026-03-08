output "api_id" {
  description = "WebSocket API Gateway ID"
  value       = aws_apigatewayv2_api.websocket.id
}

output "api_endpoint" {
  description = "WebSocket API endpoint (wss://)"
  value       = aws_apigatewayv2_api.websocket.api_endpoint
}

output "execution_arn" {
  description = "WebSocket API Gateway execution ARN (Lambda permission용)"
  value       = aws_apigatewayv2_api.websocket.execution_arn
}

output "management_endpoint" {
  description = "API Gateway Management API endpoint (POST @connections)"
  value       = "https://${aws_apigatewayv2_api.websocket.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}"
}

data "aws_region" "current" {}
