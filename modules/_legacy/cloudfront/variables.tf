# DEPRECATED: Lambda 아키텍처 모듈. K8s 전환 완료 (2026-03). 참고용으로 보존.
###############################################################################
# CloudFront Module - Variables
###############################################################################

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

variable "domain_name" {
  description = "CloudFront 커스텀 도메인 (예: my-community.shop)"
  type        = string
}

variable "s3_bucket_id" {
  description = "프론트엔드 S3 버킷 ID (OAC 버킷 정책용)"
  type        = string
}

variable "s3_bucket_arn" {
  description = "프론트엔드 S3 버킷 ARN (OAC 버킷 정책용)"
  type        = string
}

variable "s3_bucket_regional_domain_name" {
  description = "S3 버킷 리전별 도메인 (CloudFront OAC 오리진)"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM 인증서 ARN (us-east-1 리전 필수)"
  type        = string
}

variable "zone_id" {
  description = "Route 53 호스팅 영역 ID"
  type        = string
}

variable "api_domain_name" {
  description = "API 도메인 (CORS 허용 오리진용)"
  type        = string
  default     = ""
}

variable "default_root_object" {
  description = "기본 루트 객체"
  type        = string
  default     = "html/user_login.html"
}

variable "price_class" {
  description = "CloudFront 가격 등급 (PriceClass_100 = 가장 저렴, 북미+유럽만)"
  type        = string
  default     = "PriceClass_200" # 아시아 포함
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
