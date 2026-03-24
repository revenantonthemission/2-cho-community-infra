# modules/k8s_ec2/variables.tf

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "기존 VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public Subnet ID 리스트 (최소 1개)"
  type        = list(string)
}

variable "master_instance_type" {
  description = "Master 노드 인스턴스 타입"
  type        = string
  default     = "c7i-flex.large"
}

variable "worker_instance_type" {
  description = "Worker 노드 인스턴스 타입"
  type        = string
  default     = "c7i-flex.large"
}

variable "master_volume_size" {
  description = "Master 노드 EBS 크기 (GB)"
  type        = number
  default     = 30
}

variable "master_count" {
  description = "Master 노드 수 (1=단일, 3=HA)"
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3], var.master_count)
    error_message = "master_count는 1 또는 3이어야 합니다."
  }
}

variable "worker_count" {
  description = "Worker 노드 수"
  type        = number
  default     = 2
}

variable "worker_volume_sizes" {
  description = "Worker별 EBS 볼륨 크기 (GB). 길이가 worker_count보다 짧으면 마지막 값 반복"
  type        = list(number)
  default     = [30, 50]
}

variable "haproxy_enabled" {
  description = "HAProxy 로드밸런서 생성 여부 (HA Master 시 필수)"
  type        = bool
  default     = false
}

variable "haproxy_instance_type" {
  description = "HAProxy EC2 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

variable "ssh_key_name" {
  description = "SSH Key Pair 이름"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "SSH 접근 허용 CIDR 리스트"
  type        = list(string)
  default     = []
}

variable "kubernetes_version" {
  description = "kubeadm 설치할 Kubernetes 버전"
  type        = string
  default     = "1.35"
}

variable "enable_s3_uploads" {
  description = "S3 업로드 버킷 IAM 정책 생성 여부 (count 조건용)"
  type        = bool
  default     = false
}

variable "s3_uploads_bucket_arn" {
  description = "S3 업로드 버킷 ARN (enable_s3_uploads=true일 때 사용)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "SES 발신 도메인 (noreply@domain 형태로 사용)"
  type        = string
  default     = "my-community.shop"
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
