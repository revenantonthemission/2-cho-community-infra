###############################################################################
# Bootstrap Environment - Variables
###############################################################################

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 이름"
  type        = string
}

# =============================================================================
# GitHub Actions OIDC
# =============================================================================
variable "github_fork_owner" {
  description = "GitHub fork 소유자 (개인 계정명)"
  type        = string
}

variable "github_upstream_owner" {
  description = "GitHub upstream(원본) 소유자 (조직명)"
  type        = string
}
