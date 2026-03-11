###############################################################################
# Lambda Module - Variables
###############################################################################

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

# 네트워크
variable "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  type        = list(string)
}

variable "lambda_security_group_id" {
  description = "Lambda 보안 그룹 ID"
  type        = string
}

# ECR
variable "ecr_image_uri" {
  description = "ECR 이미지 URI (예: 123456789.dkr.ecr.ap-northeast-2.amazonaws.com/repo:tag)"
  type        = string
}

# EFS
variable "efs_access_point_arn" {
  description = "EFS 액세스 포인트 ARN"
  type        = string
}

variable "efs_file_system_arn" {
  description = "EFS 파일 시스템 ARN"
  type        = string
}

# RDS 연결 정보
variable "db_host" {
  description = "RDS 호스트 주소"
  type        = string
}

variable "db_port" {
  description = "RDS 포트"
  type        = number
  default     = 3306
}

variable "db_username" {
  description = "DB 사용자 이름"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "DB 비밀번호"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "DB 이름"
  type        = string
  default     = "community_service"
}

# CORS
variable "cors_allowed_origins" {
  description = "CORS 허용 오리진 목록 (FastAPI ALLOWED_ORIGINS)"
  type        = list(string)
  default     = []
}

# 애플리케이션
variable "secret_key" {
  description = "JWT SECRET_KEY"
  type        = string
  sensitive   = true
}

# 내부 API 인증 키 (EventBridge 배치 작업 호출용)
variable "internal_api_key" {
  description = "내부 API 인증 키"
  type        = string
  sensitive   = true
}

# Rate Limiter DynamoDB 설정
variable "rate_limit_dynamodb_table_arn" {
  description = "Rate Limiter DynamoDB 테이블 ARN (비어있으면 IAM 정책 미생성)"
  type        = string
  default     = ""
}

variable "rate_limit_dynamodb_table_name" {
  description = "Rate Limiter DynamoDB 테이블 이름"
  type        = string
  default     = ""
}

# Lambda 설정
variable "memory_size" {
  description = "Lambda 메모리 (MB)"
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Lambda 타임아웃 (초)"
  type        = number
  default     = 30
}

variable "provisioned_concurrency" {
  description = "Provisioned Concurrency 수 (0이면 비활성화)"
  type        = number
  default     = 0
}

variable "log_retention_days" {
  description = "CloudWatch 로그 보존 일수"
  type        = number
  default     = 14
}

# WebSocket 푸시 설정 (선택 — 미설정 시 IAM 정책 미생성)
variable "enable_websocket_push" {
  description = "WebSocket 푸시 IAM 정책 생성 여부 (plan-time 조건)"
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "ws_dynamodb_table_arn" {
  description = "WebSocket DynamoDB 테이블 ARN (비어있으면 IAM 정책 미생성)"
  type        = string
  default     = ""
}

variable "ws_dynamodb_table_name" {
  description = "WebSocket DynamoDB 테이블 이름"
  type        = string
  default     = ""
}

variable "ws_api_gateway_id" {
  description = "WebSocket API Gateway ID (ManageConnections IAM 스코핑용)"
  type        = string
  default     = ""
}

variable "ws_api_gw_endpoint" {
  description = "WebSocket API Gateway Management endpoint URL"
  type        = string
  default     = ""
}

# 이메일 발송 (SES)
variable "ses_domain_identity_arn" {
  description = "SES Domain Identity ARN (비어있으면 SES IAM 정책 미생성)"
  type        = string
  default     = ""
}

variable "email_from" {
  description = "발신 이메일 주소 (예: noreply@my-community.shop)"
  type        = string
  default     = ""
}

variable "frontend_url" {
  description = "프론트엔드 URL (이메일 인증 링크에 사용)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
