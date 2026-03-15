# DEPRECATED: Lambda 아키텍처 모듈. K8s 전환 완료 (2026-03). 참고용으로 보존.
###############################################################################
# API Gateway Module - Variables
###############################################################################

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

# Lambda 연동
variable "lambda_invoke_arn" {
  description = "Lambda 호출 ARN"
  type        = string
}

variable "lambda_function_name" {
  description = "Lambda 함수 이름"
  type        = string
}

variable "lambda_alias_name" {
  description = "Lambda Alias 이름 (Blue/Green 배포)"
  type        = string
  default     = "live"
}

# CORS
variable "cors_allowed_origins" {
  description = "CORS 허용 오리진 (allow_credentials=true 시 와일드카드 사용 불가)"
  type        = list(string)
}

# 커스텀 도메인
variable "api_domain_name" {
  description = "API 커스텀 도메인 (예: api.my-community.shop)"
  type        = string
}

variable "certificate_arn" {
  description = "ACM 인증서 ARN"
  type        = string
}

variable "zone_id" {
  description = "Route 53 호스팅 영역 ID"
  type        = string
}

# 로깅
variable "log_retention_days" {
  description = "액세스 로그 보존 일수"
  type        = number
  default     = 14
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
