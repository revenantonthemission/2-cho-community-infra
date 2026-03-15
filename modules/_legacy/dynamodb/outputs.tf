output "table_name" {
  description = "WebSocket DynamoDB 테이블 이름"
  value       = aws_dynamodb_table.ws_connections.name
}

output "table_arn" {
  description = "WebSocket DynamoDB 테이블 ARN"
  value       = aws_dynamodb_table.ws_connections.arn
}

output "rate_limit_table_name" {
  description = "Rate Limiter DynamoDB 테이블 이름"
  value       = aws_dynamodb_table.rate_limit.name
}

output "rate_limit_table_arn" {
  description = "Rate Limiter DynamoDB 테이블 ARN"
  value       = aws_dynamodb_table.rate_limit.arn
}
