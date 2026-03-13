# DEPRECATED: Lambda 아키텍처 모듈. K8s 전환 완료 (2026-03). 참고용으로 보존.
###############################################################################
# EventBridge Module - Variables
###############################################################################

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

variable "api_endpoint" {
  description = "API Gateway 엔드포인트 URL (https://api.example.com)"
  type        = string
}

variable "internal_api_key" {
  description = "내부 API 인증 키 (X-Internal-Key 헤더)"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
