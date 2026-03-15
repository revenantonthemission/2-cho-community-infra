# DEPRECATED: Lambda 아키텍처 모듈. K8s 전환 완료 (2026-03). 참고용으로 보존.
###############################################################################
# CloudWatch Module - Variables
###############################################################################

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "log_retention_days" {
  description = "로그 보존 일수"
  type        = number
  default     = 14
}

# Lambda 모니터링
variable "lambda_function_name" {
  description = "Lambda 함수 이름"
  type        = string
}

variable "lambda_error_threshold" {
  description = "Lambda 에러 알람 임계치"
  type        = number
  default     = 5
}

variable "lambda_duration_threshold_ms" {
  description = "Lambda 실행 시간 알람 임계치 (밀리초)"
  type        = number
  default     = 25000
}

# RDS 모니터링
variable "rds_instance_id" {
  description = "RDS 인스턴스 ID"
  type        = string
}

variable "rds_cpu_threshold" {
  description = "RDS CPU 알람 임계치 (%)"
  type        = number
  default     = 80
}

variable "rds_free_storage_threshold_bytes" {
  description = "RDS 여유 스토리지 알람 임계치 (bytes)"
  type        = number
  default     = 2147483648 # 2GB
}

variable "rds_connection_threshold" {
  description = "RDS 연결 수 알람 임계치"
  type        = number
  default     = 40
}

# API Gateway (대시보드 위젯용)
variable "api_gateway_id" {
  description = "API Gateway ID (대시보드 위젯용)"
  type        = string
}

# 알람 액션
variable "alarm_sns_topic_arn" {
  description = "알람 발생 시 알림을 보낼 SNS 토픽 ARN (빈 문자열이면 비활성화)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
