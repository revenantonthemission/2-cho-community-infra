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

variable "worker1_volume_size" {
  description = "Worker 1 EBS 크기 (GB)"
  type        = number
  default     = 30
}

variable "worker2_volume_size" {
  description = "Worker 2 EBS 크기 (GB) — MySQL PV + Prometheus"
  type        = number
  default     = 50
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

variable "s3_uploads_bucket_arn" {
  description = "S3 업로드 버킷 ARN (설정 시 S3 읽기/쓰기 권한 부여)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
