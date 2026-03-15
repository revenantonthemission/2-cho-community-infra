###############################################################################
# Lambda Module - Outputs
###############################################################################

output "function_name" {
  description = "Lambda 함수 이름"
  value       = aws_lambda_function.backend.function_name
}

output "function_arn" {
  description = "Lambda 함수 ARN"
  value       = aws_lambda_function.backend.arn
}

output "invoke_arn" {
  description = "Lambda 호출 ARN (API Gateway 연동용)"
  value       = aws_lambda_function.backend.invoke_arn
}

output "role_arn" {
  description = "Lambda IAM 역할 ARN"
  value       = aws_iam_role.lambda.arn
}

output "log_group_name" {
  description = "CloudWatch 로그 그룹 이름"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "alias_invoke_arn" {
  description = "Lambda Alias 호출 ARN (API Gateway 연동용)"
  value       = aws_lambda_alias.live.invoke_arn
}

output "alias_name" {
  description = "Lambda Alias 이름"
  value       = aws_lambda_alias.live.name
}

output "secret_key_ssm_arn" {
  description = "SECRET_KEY SSM 파라미터 ARN"
  value       = aws_ssm_parameter.secret_key.arn
}

output "secret_key_ssm_name" {
  description = "SECRET_KEY SSM 파라미터 이름"
  value       = aws_ssm_parameter.secret_key.name
}

output "internal_api_key_ssm_name" {
  description = "INTERNAL_API_KEY SSM 파라미터 이름"
  value       = aws_ssm_parameter.internal_api_key.name
}
