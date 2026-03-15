output "function_name" {
  description = "WebSocket Lambda 함수 이름"
  value       = aws_lambda_function.websocket.function_name
}

output "function_arn" {
  description = "WebSocket Lambda 함수 ARN"
  value       = aws_lambda_function.websocket.arn
}

output "invoke_arn" {
  description = "WebSocket Lambda 호출 ARN"
  value       = aws_lambda_function.websocket.invoke_arn
}
