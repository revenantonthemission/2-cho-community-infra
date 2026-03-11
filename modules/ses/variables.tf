# modules/ses/variables.tf
# SES 이메일 발송 모듈 변수

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev/staging/prod)"
  type        = string
}

variable "domain_name" {
  description = "SES 도메인 (예: my-community.shop)"
  type        = string
}

variable "zone_id" {
  description = "Route 53 Hosted Zone ID (DNS 검증용)"
  type        = string
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
