# DEPRECATED: Lambda 아키텍처 모듈. K8s 전환 완료 (2026-03). 참고용으로 보존.
variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 이름"
  type        = string
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
