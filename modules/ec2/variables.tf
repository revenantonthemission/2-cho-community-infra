###############################################################################
# EC2 Module - Variables
###############################################################################

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

variable "public_subnet_id" {
  description = "퍼블릭 서브넷 ID (Bastion 배치)"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Bastion 보안 그룹 ID"
  type        = string
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key" {
  description = "SSH 공개키 (빈 문자열이면 키페어 생성 안 함)"
  type        = string
  default     = ""
}

variable "create_bastion" {
  description = "배스천 호스트 생성 여부"
  type        = bool
  default     = true
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
