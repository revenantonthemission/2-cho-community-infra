variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 이름"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "dynamodb_table_arn" {
  description = "DynamoDB ws_connections 테이블 ARN"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB ws_connections 테이블 이름"
  type        = string
}

variable "secret_key_ssm_arn" {
  description = "SECRET_KEY SSM 파라미터 ARN"
  type        = string
}

variable "secret_key_ssm_name" {
  description = "SECRET_KEY SSM 파라미터 이름"
  type        = string
}

variable "ws_api_endpoint" {
  description = "WebSocket API Gateway Management endpoint URL"
  type        = string
}

variable "ws_api_gateway_id" {
  description = "WebSocket API Gateway ID (ManageConnections IAM 스코핑용)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "로그 보존 일수"
  type        = number
  default     = 14
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
