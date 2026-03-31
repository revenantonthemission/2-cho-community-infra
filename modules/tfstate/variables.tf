###############################################################################
# Terraform Remote State Module - Variables
###############################################################################

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

# 리소스 이름에는 미사용 (환경 공유 리소스). 모듈 인터페이스 일관성을 위해 유지
variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}

variable "account_id" {
  description = "AWS 계정 ID (KMS 키 정책용)"
  type        = string
}

variable "github_actions_role_arns" {
  description = "KMS 키 접근을 허용할 GitHub Actions IAM 역할 ARN 목록"
  type        = list(string)
  default     = []
}
