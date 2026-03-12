###############################################################################
# S3 Module - Variables
###############################################################################

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

variable "cloudtrail_log_retention_days" {
  description = "CloudTrail 로그 보존 일수"
  type        = number
  default     = 90
}

variable "create_uploads_bucket" {
  description = "업로드 S3 버킷 생성 여부"
  type        = bool
  default     = false
}

variable "uploads_cors_origins" {
  description = "업로드 버킷 CORS 허용 오리진"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
