###############################################################################
# VPC Module - Variables
###############################################################################

variable "project" {
  description = "프로젝트 이름 (리소스 네이밍에 사용)"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment는 dev, staging, prod 중 하나여야 합니다."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "유효한 CIDR 블록이어야 합니다."
  }
}

variable "az_count" {
  description = "사용할 가용 영역 수"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count는 2 또는 3이어야 합니다."
  }
}

variable "single_nat_gateway" {
  description = "true: NAT Gateway 1개 (비용 절감), false: AZ별 1개 (고가용성)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "모든 리소스에 적용할 공통 태그"
  type        = map(string)
  default     = {}
}
