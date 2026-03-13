# K8s 통합 아키텍처 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Staging/Prod 환경을 K8s HA 클러스터로 통합하고, Kustomize 기반 환경 분기를 구축한다.

**Architecture:** 기존 `modules/k8s_ec2/`를 HA 지원으로 확장 (master_count, haproxy). Staging/Prod main.tf를 K8s+RDS 구성으로 재작성. K8s 매니페스트를 Kustomize base/overlay로 재구조화.

**Tech Stack:** Terraform, kubeadm, HAProxy, Kustomize, Helm, GitHub Actions

**설계 문서:** `docs/plans/2026-03-14-k8s-unified-design.md`

---

## Phase 1: k8s_ec2 모듈 확장

### Task 1: 변수 추가 — master_count, worker_count, haproxy

**Files:**
- Modify: `modules/k8s_ec2/variables.tf:41-51` (worker1/worker2 volume → worker_volume_sizes)

**Step 1: 기존 worker1/worker2 volume 변수를 교체하고 신규 변수 추가**

`modules/k8s_ec2/variables.tf`에서 `worker1_volume_size`(41-45), `worker2_volume_size`(47-51)를 제거하고 아래로 교체:

```hcl
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
```

**Step 2: 검증**

```bash
cd environments/dev && terraform validate
```

Expected: Success (아직 main.tf에서 사용하지 않으므로 경고 없음)

**Step 3: 커밋**

```bash
git add modules/k8s_ec2/variables.tf
git commit -m "feat(k8s_ec2): add master_count, worker_count, haproxy variables for HA support"
```

---

### Task 2: Master 다중화 — count 기반 변경

**Files:**
- Modify: `modules/k8s_ec2/main.tf:35-68` (master instance + EIP)

**Step 1: Master 인스턴스를 count 기반으로 변경**

`modules/k8s_ec2/main.tf`에서 `aws_instance.master`(35-58)를 수정:

```hcl
resource "aws_instance" "master" {
  count = var.master_count

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.master_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  vpc_security_group_ids = local.master_sg_ids
  iam_instance_profile   = aws_iam_instance_profile.k8s_node.name

  source_dest_check = false

  user_data = templatefile("${path.module}/userdata.sh", {
    kubernetes_version = var.kubernetes_version
  })

  root_block_device {
    volume_size = var.master_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-master-${count.index + 1}"
    Role = "master"
  })
}
```

**Step 2: EIP를 count 기반으로 변경**

`aws_eip.master`(60-68)를 수정:

```hcl
resource "aws_eip" "master" {
  count = var.master_count

  instance = aws_instance.master[count.index].id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-master-eip-${count.index + 1}"
  })
}
```

**Step 3: 검증**

```bash
cd environments/dev && terraform validate
```

Expected: 오류 발생 가능 (outputs가 아직 단수형 참조). Task 4에서 해결.

**Step 4: 커밋 (검증 통과 후)**

```bash
git add modules/k8s_ec2/main.tf
git commit -m "feat(k8s_ec2): make master instances count-based for HA support"
```

---

### Task 3: Worker 동적 수 + HAProxy 인스턴스

**Files:**
- Modify: `modules/k8s_ec2/main.tf:71-96` (worker instances)
- Create: `modules/k8s_ec2/haproxy_userdata.sh`

**Step 1: Worker 인스턴스의 count와 volume을 동적으로 변경**

`modules/k8s_ec2/main.tf`에서 `aws_instance.worker`(71-96)를 수정:

```hcl
resource "aws_instance" "worker" {
  count = var.worker_count

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.worker_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  vpc_security_group_ids = local.worker_sg_ids
  iam_instance_profile   = aws_iam_instance_profile.k8s_node.name

  source_dest_check = false

  user_data = templatefile("${path.module}/userdata.sh", {
    kubernetes_version = var.kubernetes_version
  })

  root_block_device {
    volume_size = var.worker_volume_sizes[min(count.index, length(var.worker_volume_sizes) - 1)]
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-worker-${count.index + 1}"
    Role = "worker"
  })
}
```

**Step 2: HAProxy userdata 스크립트 생성**

`modules/k8s_ec2/haproxy_userdata.sh` 생성:

```bash
#!/bin/bash
set -euxo pipefail

# HAProxy 설치
dnf install -y haproxy

# HAProxy 설정 작성
cat > /etc/haproxy/haproxy.cfg << 'EOF'
global
    log /dev/log local0
    maxconn 2048

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    retries 3

frontend k8s_api
    bind *:6443
    default_backend k8s_masters

backend k8s_masters
    option httpchk GET /healthz
    http-check expect status 200
    balance roundrobin
${master_backends}

frontend stats
    bind *:9000
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
EOF

systemctl enable --now haproxy
```

**Step 3: HAProxy EC2 + EIP 리소스 추가**

`modules/k8s_ec2/main.tf` 맨 끝에 추가:

```hcl
# =============================================================================
# HAProxy Load Balancer (HA Master 전용)
# =============================================================================
resource "aws_instance" "haproxy" {
  count = var.haproxy_enabled ? 1 : 0

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.haproxy_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = local.haproxy_sg_ids
  iam_instance_profile   = aws_iam_instance_profile.k8s_node.name

  user_data = templatefile("${path.module}/haproxy_userdata.sh", {
    master_backends = join("\n", [
      for idx, inst in aws_instance.master :
      "    server master-${idx + 1} ${inst.private_ip}:6443 check check-ssl verify none"
    ])
  })

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-haproxy"
    Role = "haproxy"
  })
}

resource "aws_eip" "haproxy" {
  count = var.haproxy_enabled ? 1 : 0

  instance = aws_instance.haproxy[0].id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-haproxy-eip"
  })
}
```

**Step 4: locals에 haproxy_sg_ids 추가**

`modules/k8s_ec2/main.tf`의 `locals` 블록(19-32)에 추가:

```hcl
locals {
  # ... 기존 master_sg_ids, worker_sg_ids 유지 ...

  haproxy_sg_ids = concat(
    [aws_security_group.k8s_haproxy[0].id],
    length(var.allowed_ssh_cidrs) > 0 ? [aws_security_group.k8s_ssh[0].id] : []
  )
}
```

주의: `haproxy_sg_ids`에서 `k8s_haproxy[0]`를 참조하므로, `haproxy_enabled=false`일 때 locals 평가 오류 가능. 대안으로 HAProxy SG ID를 인스턴스 리소스에 직접 inline:

```hcl
# aws_instance.haproxy 내부
vpc_security_group_ids = concat(
  var.haproxy_enabled ? [aws_security_group.k8s_haproxy[0].id] : [],
  [aws_security_group.k8s_internal.id],
  length(var.allowed_ssh_cidrs) > 0 ? [aws_security_group.k8s_ssh[0].id] : []
)
```

이 경우 locals에서 `haproxy_sg_ids`를 제거하고 직접 참조.

**Step 5: 커밋**

```bash
git add modules/k8s_ec2/main.tf modules/k8s_ec2/haproxy_userdata.sh
git commit -m "feat(k8s_ec2): add dynamic worker count and conditional HAProxy LB"
```

---

### Task 4: Security Group 확장 — HAProxy SG

**Files:**
- Modify: `modules/k8s_ec2/sg.tf:4-51` (master SG에 HAProxy 인바운드 추가)
- Modify: `modules/k8s_ec2/sg.tf` (HAProxy SG 추가)

**Step 1: HAProxy Security Group 추가**

`modules/k8s_ec2/sg.tf` 맨 끝에 추가:

```hcl
# =============================================================================
# HAProxy Security Group (HA Master LB)
# =============================================================================
resource "aws_security_group" "k8s_haproxy" {
  count = var.haproxy_enabled ? 1 : 0

  name        = "${var.project}-${var.environment}-k8s-haproxy"
  description = "Security group for K8s HAProxy load balancer"
  vpc_id      = var.vpc_id

  # K8s API (6443) — 관리자 접근
  ingress {
    description = "K8s API from admin"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # K8s API (6443) — K8s 내부 노드 (kubelet → API server)
  ingress {
    description     = "K8s API from internal nodes"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_internal.id]
  }

  # HAProxy Stats (9000) — 관리자 전용
  ingress {
    description = "HAProxy stats from admin"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-haproxy"
  })

  lifecycle {
    create_before_destroy = true
  }
}
```

**Step 2: Master SG에 HAProxy로부터의 6443 인바운드 추가**

`modules/k8s_ec2/sg.tf`의 `k8s_master` SG(4-51) 내부, 기존 6443 ingress 아래에 추가:

```hcl
  # K8s API (6443) — HAProxy에서 접근 (HA 구성)
  dynamic "ingress" {
    for_each = var.haproxy_enabled ? [1] : []
    content {
      description     = "K8s API from HAProxy"
      from_port       = 6443
      to_port         = 6443
      protocol        = "tcp"
      security_groups = [aws_security_group.k8s_haproxy[0].id]
    }
  }
```

**Step 3: 검증**

```bash
cd environments/dev && terraform validate
```

**Step 4: 커밋**

```bash
git add modules/k8s_ec2/sg.tf
git commit -m "feat(k8s_ec2): add HAProxy security group and master SG ingress rule"
```

---

### Task 5: Outputs 확장

**Files:**
- Modify: `modules/k8s_ec2/outputs.tf` (전체 재작성)

**Step 1: Outputs를 복수형 + HAProxy + SG ID로 확장**

`modules/k8s_ec2/outputs.tf` 전체 교체:

```hcl
# Master Nodes
output "master_public_ips" {
  description = "Master 노드 EIP 목록"
  value       = aws_eip.master[*].public_ip
}

output "master_private_ips" {
  description = "Master 노드 Private IP 목록"
  value       = aws_instance.master[*].private_ip
}

output "master_instance_ids" {
  description = "Master 인스턴스 ID 목록"
  value       = aws_instance.master[*].id
}

# Worker Nodes
output "worker_public_ips" {
  description = "Worker 노드 Public IP 목록"
  value       = aws_instance.worker[*].public_ip
}

output "worker_private_ips" {
  description = "Worker 노드 Private IP 목록"
  value       = aws_instance.worker[*].private_ip
}

output "worker_instance_ids" {
  description = "Worker 인스턴스 ID 목록"
  value       = aws_instance.worker[*].id
}

# HAProxy
output "haproxy_public_ip" {
  description = "HAProxy EIP (HA 구성 시)"
  value       = var.haproxy_enabled ? aws_eip.haproxy[0].public_ip : null
}

output "haproxy_private_ip" {
  description = "HAProxy Private IP (HA 구성 시)"
  value       = var.haproxy_enabled ? aws_instance.haproxy[0].private_ip : null
}

# Security Groups (환경 main.tf에서 RDS SG 연동용)
output "k8s_internal_sg_id" {
  description = "K8s Internal SG ID (RDS 접근 허용 등 외부 연동)"
  value       = aws_security_group.k8s_internal.id
}
```

**Step 2: Dev 환경 outputs.tf 업데이트**

`environments/dev/outputs.tf`(69-77)에서 K8s 관련 outputs 수정:

```hcl
# K8s Cluster
output "k8s_master_public_ips" {
  description = "K8s Master EIP 목록"
  value       = var.create_k8s_cluster ? module.k8s_ec2[0].master_public_ips : []
}

output "k8s_worker_public_ips" {
  description = "K8s Worker Public IP 목록"
  value       = var.create_k8s_cluster ? module.k8s_ec2[0].worker_public_ips : []
}

output "k8s_haproxy_public_ip" {
  description = "K8s HAProxy EIP (HA 구성 시)"
  value       = var.create_k8s_cluster ? module.k8s_ec2[0].haproxy_public_ip : null
}
```

**Step 3: Dev 환경 DNS records의 output 참조 확인**

`environments/dev/main.tf:255`에서 `module.k8s_ec2[0].worker_public_ips`는 이미 복수형이므로 변경 불필요.

**Step 4: 검증**

```bash
cd environments/dev && terraform validate
```

Expected: Success

**Step 5: 커밋**

```bash
git add modules/k8s_ec2/outputs.tf environments/dev/outputs.tf
git commit -m "feat(k8s_ec2): extend outputs for HA (plural masters, haproxy, SG ID)"
```

---

### Task 6: Dev 환경 Terraform State Migration

**주의: 이 태스크는 실제 AWS 접근이 필요합니다. `terraform state mv`는 원격 S3 state를 수정합니다.**

**Files:**
- 없음 (state 조작만)

**Step 1: 현재 state 확인**

```bash
cd environments/dev
terraform state list | grep k8s_ec2
```

Expected output:
```
module.k8s_ec2[0].aws_eip.master
module.k8s_ec2[0].aws_instance.master
module.k8s_ec2[0].aws_instance.worker[0]
module.k8s_ec2[0].aws_instance.worker[1]
...
```

**Step 2: Master 리소스 주소 이전**

```bash
terraform state mv \
  'module.k8s_ec2[0].aws_instance.master' \
  'module.k8s_ec2[0].aws_instance.master[0]'

terraform state mv \
  'module.k8s_ec2[0].aws_eip.master' \
  'module.k8s_ec2[0].aws_eip.master[0]'
```

**Step 3: Plan으로 변경 없음 확인**

```bash
terraform plan -var-file=terraform.tfvars -var-file=secret.tfvars
```

Expected: `No changes. Your infrastructure matches the configuration.` 또는 태그/이름 변경만 표시 (master → master-1).

Master 이름이 `k8s-master` → `k8s-master-1`로 변경되는 것은 태그만 변경이므로 안전합니다 (인스턴스 재생성 없음).

**Step 4: Apply (태그 변경만)**

```bash
terraform apply -var-file=terraform.tfvars -var-file=secret.tfvars
```

---

## Phase 2: Staging 환경 Terraform

### Task 7: Staging variables.tf 재작성

**Files:**
- Modify: `environments/staging/variables.tf` (전체 재작성 — Lambda 변수 제거, K8s 변수 추가)

**Step 1: Dev의 variables.tf를 기반으로 Staging용 재작성**

`environments/staging/variables.tf`를 다음과 같이 교체. Dev의 `variables.tf`(196 lines)를 복사하되:
- Lambda 관련 변수 제거 (secret_key, internal_api_key, lambda_*)
- K8s 변수 추가 (k8s_ssh_key_name, k8s_allowed_ssh_cidrs, create_k8s_cluster)
- RDS 변수 유지 (Staging/Prod는 RDS 사용)

핵심 차이: Dev에는 없고 Staging에 있어야 할 변수:
- RDS 관련 변수 전부 (Dev에도 이미 존재)
- K8s 관련 변수 (Dev와 동일)

핵심 차이: Staging에서 제거할 변수:
- `lambda_image_tag`, `lambda_memory_size`, `lambda_timeout`, `lambda_provisioned_concurrency`
- `secret_key` (Lambda SSM용), `internal_api_key`
- `lambda_log_retention_days`
- `cloudwatch_log_retention_days` (Lambda CloudWatch용)

**Step 2: 검증**

```bash
cd environments/staging && terraform validate
```

주의: `main.tf`가 아직 Lambda 모듈을 참조하므로 오류 발생. Task 8 이후 통합 검증.

**Step 3: 커밋**

```bash
git add environments/staging/variables.tf
git commit -m "feat(staging): rewrite variables.tf for K8s architecture (remove Lambda vars)"
```

---

### Task 8: Staging main.tf 재작성

**Files:**
- Modify: `environments/staging/main.tf` (전체 재작성 — Lambda → K8s + RDS)

**Step 1: Dev의 main.tf를 기반으로 Staging용 재작성**

`environments/staging/main.tf`를 다음 구조로 교체:

```hcl
###############################################################################
# Staging Environment - Main Configuration
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-community-tfstate"
    key            = "staging/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# Module 0: IAM
# =============================================================================
module "iam" {
  source = "../../modules/iam"

  project     = var.project
  environment = var.environment

  admin_username       = var.admin_username
  create_deployer_role = var.create_deployer_role

  tags = local.common_tags
}

# =============================================================================
# Module 1: VPC
# =============================================================================
module "vpc" {
  source                = "../../modules/vpc"
  project               = var.project
  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  az_count              = var.az_count
  single_nat_gateway    = var.single_nat_gateway
  bastion_allowed_cidrs = var.bastion_allowed_cidrs

  tags = local.common_tags
}

# =============================================================================
# Module 2: S3 (uploads + CloudTrail logs)
# =============================================================================
module "s3" {
  source = "../../modules/s3"

  project     = var.project
  environment = var.environment

  cloudtrail_log_retention_days = var.cloudtrail_log_retention_days

  create_uploads_bucket = true
  uploads_cors_origins  = ["https://staging.my-community.shop"]

  tags = local.common_tags
}

# =============================================================================
# Module 3: Route 53 + ACM
# =============================================================================
module "route53" {
  source = "../../modules/route53"

  domain_name = var.domain_name
}

module "acm" {
  source = "../../modules/acm"

  project     = var.project
  environment = var.environment

  domain_name               = "api-staging.${var.domain_name}"
  subject_alternative_names = ["staging.${var.domain_name}", "ws-staging.${var.domain_name}"]
  zone_id                   = module.route53.zone_id

  tags = local.common_tags
}

# =============================================================================
# Module 3.5: SES
# =============================================================================
module "ses" {
  source = "../../modules/ses"

  project     = var.project
  environment = var.environment

  domain_name = var.domain_name
  zone_id     = module.route53.zone_id

  tags = local.common_tags
}

# =============================================================================
# Module 4: ECR
# =============================================================================
module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  image_retention_count = var.ecr_image_retention_count

  additional_repositories = [
    "${var.project}-${var.environment}-backend-k8s",
    "${var.project}-${var.environment}-frontend-k8s",
  ]

  tags = local.common_tags
}

# =============================================================================
# Module 5: RDS
# =============================================================================
module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  private_subnet_ids    = module.vpc.private_subnet_ids
  rds_security_group_id = module.vpc.rds_security_group_id

  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  multi_az              = var.rds_multi_az
  backup_retention_days = var.rds_backup_retention_days
  deletion_protection   = var.rds_deletion_protection

  tags = local.common_tags
}

# =============================================================================
# Module 10: EC2 + EIP (Bastion Host) — 비활성화
# =============================================================================
module "ec2" {
  source = "../../modules/ec2"

  project     = var.project
  environment = var.environment

  public_subnet_id          = module.vpc.public_subnet_ids[0]
  bastion_security_group_id = module.vpc.bastion_security_group_id

  instance_type  = var.bastion_instance_type
  ssh_public_key = var.bastion_ssh_public_key

  tags = local.common_tags
}

# =============================================================================
# Module 11: CloudTrail
# =============================================================================
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  project     = var.project
  environment = var.environment

  cloudtrail_s3_bucket_id = module.s3.cloudtrail_logs_bucket_id
  log_retention_days      = var.cloudtrail_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# K8s Cluster (HA: Master 3 + Worker 2 + HAProxy)
# =============================================================================
module "k8s_ec2" {
  source = "../../modules/k8s_ec2"
  count  = var.create_k8s_cluster ? 1 : 0

  project     = var.project
  environment = var.environment

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  master_count          = 3
  worker_count          = 2
  haproxy_enabled       = true
  haproxy_instance_type = "t3.micro"

  ssh_key_name      = var.k8s_ssh_key_name
  allowed_ssh_cidrs = var.k8s_allowed_ssh_cidrs

  s3_uploads_bucket_arn = module.s3.uploads_bucket_arn

  tags = local.common_tags
}

# K8s → RDS 접근 허용
resource "aws_security_group_rule" "rds_from_k8s" {
  count = var.create_k8s_cluster ? 1 : 0

  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  description              = "MySQL from K8s internal nodes"
  security_group_id        = module.vpc.rds_security_group_id
  source_security_group_id = module.k8s_ec2[0].k8s_internal_sg_id
}

# K8s DNS Records (Worker → Staging 도메인)
resource "aws_route53_record" "k8s" {
  for_each = var.create_k8s_cluster ? toset([
    "staging",
    "api-staging",
    "ws-staging",
    "grafana-staging",
  ]) : toset([])

  zone_id = module.route53.zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = module.k8s_ec2[0].worker_public_ips
}
```

**Step 2: locals.tf 확인**

`environments/staging/locals.tf`에 `common_tags` 정의가 있는지 확인. Dev와 동일한 구조여야 함:

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
  }
}
```

없으면 Dev의 것을 복사.

**Step 3: 커밋**

```bash
git add environments/staging/main.tf environments/staging/locals.tf
git commit -m "feat(staging): rewrite main.tf for K8s + RDS architecture"
```

---

### Task 9: Staging terraform.tfvars + outputs.tf 업데이트

**Files:**
- Modify: `environments/staging/terraform.tfvars` (Lambda → K8s 값)
- Modify: `environments/staging/outputs.tf` (Lambda outputs → K8s outputs)

**Step 1: terraform.tfvars 재작성**

```hcl
###############################################################################
# Staging Environment — terraform.tfvars
###############################################################################

# General
aws_region  = "ap-northeast-2"
project     = "my-community"
environment = "staging"

# IAM
admin_username       = "admin-staging"
create_deployer_role = false

# VPC
vpc_cidr              = "10.1.0.0/16"
az_count              = 2
single_nat_gateway    = true
bastion_allowed_cidrs = []

# S3 / CloudTrail
cloudtrail_log_retention_days = 60

# Route 53 / ACM
domain_name = "my-community.shop"

# ECR
ecr_image_retention_count = 10

# RDS
rds_engine_version        = "8.0"
rds_instance_class        = "db.t3.small"
rds_allocated_storage     = 20
rds_max_allocated_storage = 100
rds_multi_az              = false
rds_backup_retention_days = 3
rds_deletion_protection   = false

db_name     = "community_service"
db_username = "admin"
# db_password → secret.tfvars

# EC2 (Bastion — 비활성화)
bastion_instance_type = "t4g.micro"

# K8s
create_k8s_cluster = true
# k8s_ssh_key_name, k8s_allowed_ssh_cidrs → secret.tfvars
```

**Step 2: outputs.tf 재작성**

Dev의 `outputs.tf`를 기반으로 Staging 재작성 (Lambda outputs 제거, K8s outputs 추가):

```hcl
###############################################################################
# Staging Environment — Outputs
###############################################################################

# IAM
output "admin_user_name" {
  description = "IAM admin 사용자 이름"
  value       = module.iam.admin_user_name
  sensitive   = true
}

output "admin_initial_password" {
  description = "IAM admin 초기 비밀번호"
  value       = module.iam.admin_initial_password
  sensitive   = true
}

# VPC
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public 서브넷 ID 목록"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private 서브넷 ID 목록"
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_ips" {
  description = "NAT Gateway EIP 목록"
  value       = module.vpc.nat_gateway_ips
}

# S3
output "uploads_bucket_domain" {
  description = "Uploads S3 버킷 도메인"
  value       = module.s3.uploads_bucket_domain
}

# ECR
output "ecr_repository_url" {
  description = "ECR 레포지토리 URL"
  value       = module.ecr.repository_url
}

# RDS
output "rds_endpoint" {
  description = "RDS 엔드포인트"
  value       = module.rds.endpoint
}

# Bastion
output "bastion_public_ip" {
  description = "Bastion 호스트 Public IP"
  value       = module.ec2.bastion_public_ip
}

# SES
output "ses_domain_identity_arn" {
  description = "SES 도메인 Identity ARN"
  value       = module.ses.domain_identity_arn
}

# K8s Cluster
output "k8s_master_public_ips" {
  description = "K8s Master EIP 목록"
  value       = var.create_k8s_cluster ? module.k8s_ec2[0].master_public_ips : []
}

output "k8s_worker_public_ips" {
  description = "K8s Worker Public IP 목록"
  value       = var.create_k8s_cluster ? module.k8s_ec2[0].worker_public_ips : []
}

output "k8s_haproxy_public_ip" {
  description = "K8s HAProxy EIP"
  value       = var.create_k8s_cluster ? module.k8s_ec2[0].haproxy_public_ip : null
}
```

**Step 3: 검증**

```bash
cd environments/staging && terraform validate
```

Expected: Success (secret.tfvars 없이도 validate는 통과)

**Step 4: 커밋**

```bash
git add environments/staging/terraform.tfvars environments/staging/outputs.tf
git commit -m "feat(staging): update tfvars and outputs for K8s + RDS architecture"
```

---

### Task 10: Staging 검증 — terraform plan

**Step 1: Plan 실행 (더미 민감 변수)**

```bash
cd environments/staging
terraform init
terraform plan \
  -var-file=terraform.tfvars \
  -var="db_password=dummy" \
  -var="create_k8s_cluster=true" \
  -var="k8s_ssh_key_name=dummy-key" \
  -var='k8s_allowed_ssh_cidrs=["0.0.0.0/0"]'
```

Expected: 리소스 목록 출력 (EC2 ×6, EIP ×4, SG ×5, RDS, VPC 등). 오류 없어야 함.

**Step 2: 리소스 수 확인**

`Plan: N to add, 0 to change, 0 to destroy`에서 N이 합리적인지 확인.

**Step 3: 커밋 (검증 완료 확인)**

```bash
git commit --allow-empty -m "chore(staging): terraform plan validated successfully"
```

---

## Phase 3: Kustomize 전환

### Task 11: base 디렉토리 생성 — 공통 매니페스트 이동

**Files:**
- Create: `k8s/base/` 디렉토리 구조
- Move: `k8s/app/`, `k8s/cert/`, `k8s/network/`, `k8s/storage/storageclass.yaml`, `k8s/namespaces.yaml` → `k8s/base/`
- Create: `k8s/base/kustomization.yaml`

**Step 1: base 디렉토리 생성 및 파일 이동**

```bash
cd /Users/revenantonthemission/my-community/2-cho-community-infra/k8s

mkdir -p base/app base/cert base/network base/storage

# 공통 매니페스트 이동 (mysql.yaml, cronjob-mysql-backup.yaml 제외 — Dev 전용)
cp app/api-deployment.yaml base/app/
cp app/api-hpa.yaml base/app/
cp app/api-service.yaml base/app/
cp app/api-servicemonitor.yaml base/app/
cp app/configmap.yaml base/app/
cp app/cronjob-ecr-refresh.yaml base/app/
cp app/cronjob-feed-recompute.yaml base/app/
cp app/cronjob-token-cleanup.yaml base/app/
cp app/fe-deployment.yaml base/app/
cp app/fe-service.yaml base/app/
cp app/ingress.yaml base/app/
cp app/networkpolicy.yaml base/app/
cp app/ws-deployment.yaml base/app/

cp cert/clusterissuer.yaml base/cert/
cp network/networkpolicy-data.yaml base/network/
cp storage/storageclass.yaml base/storage/
cp namespaces.yaml base/
```

**Step 2: base 매니페스트에서 환경별 값을 중립화**

`base/app/configmap.yaml`에서 환경별 값을 placeholder로:
- `DB_HOST`, `DB_USER`, `S3_BUCKET_NAME`, `ALLOWED_ORIGINS`, `FRONTEND_URL`, `TRUSTED_PROXIES` → overlay에서 패치

`base/app/ingress.yaml`에서 호스트 목록을 Dev 기본값으로 유지 (overlay에서 전체 교체).

이미지 참조는 base에 Dev 기본값을 유지하고, Kustomize `images` 변환기로 overlay에서 오버라이드.

**Step 3: kustomization.yaml 생성**

`k8s/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespaces.yaml
  - cert/clusterissuer.yaml
  - network/networkpolicy-data.yaml
  - storage/storageclass.yaml
  - app/api-deployment.yaml
  - app/api-service.yaml
  - app/api-hpa.yaml
  - app/api-servicemonitor.yaml
  - app/fe-deployment.yaml
  - app/fe-service.yaml
  - app/ws-deployment.yaml
  - app/ingress.yaml
  - app/configmap.yaml
  - app/networkpolicy.yaml
  - app/cronjob-ecr-refresh.yaml
  - app/cronjob-feed-recompute.yaml
  - app/cronjob-token-cleanup.yaml
```

**Step 4: 검증**

```bash
kubectl kustomize k8s/base/ > /dev/null
```

Expected: YAML 출력 성공 (클러스터 접근 불필요)

**Step 5: 커밋**

```bash
git add k8s/base/
git commit -m "feat(k8s): create Kustomize base directory with common manifests"
```

---

### Task 12: Dev overlay 생성

**Files:**
- Create: `k8s/overlays/dev/kustomization.yaml`
- Create: `k8s/overlays/dev/configmap-patch.yaml`
- Create: `k8s/overlays/dev/ingress-patch.yaml`
- Move: `k8s/app/mysql.yaml` → `k8s/overlays/dev/mysql.yaml`
- Move: `k8s/app/cronjob-mysql-backup.yaml` → `k8s/overlays/dev/cronjob-mysql-backup.yaml`
- Move: `k8s/storage/pv-*.yaml` → `k8s/overlays/dev/storage/`

**Step 1: Dev overlay 디렉토리 구조 생성**

```bash
mkdir -p k8s/overlays/dev/storage
```

**Step 2: Dev 전용 파일 이동**

```bash
cp k8s/app/mysql.yaml k8s/overlays/dev/
cp k8s/app/cronjob-mysql-backup.yaml k8s/overlays/dev/
cp k8s/storage/pv-mysql.yaml k8s/overlays/dev/storage/
cp k8s/storage/pv-prometheus.yaml k8s/overlays/dev/storage/
cp k8s/storage/pv-redis.yaml k8s/overlays/dev/storage/
cp k8s/storage/pv-uploads.yaml k8s/overlays/dev/storage/
# pvc-uploads.yaml은 PV에 종속 → overlay로 이동
cp k8s/storage/pvc-uploads.yaml k8s/overlays/dev/storage/
```

**Step 3: Dev kustomization.yaml 생성**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base
  - mysql.yaml
  - cronjob-mysql-backup.yaml
  - storage/pv-mysql.yaml
  - storage/pv-prometheus.yaml
  - storage/pv-redis.yaml
  - storage/pv-uploads.yaml
  - storage/pvc-uploads.yaml

patches:
  - path: configmap-patch.yaml
  - path: ingress-patch.yaml
```

**Step 4: configmap-patch.yaml 생성**

Dev 환경의 현재 configmap.yaml 값을 사용한 strategic merge patch:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: community-config
  namespace: app
data:
  DB_HOST: "mysql.data.svc.cluster.local"
  DB_USER: "manager_dev"
  DB_NAME: "community_service"
  S3_BUCKET_NAME: "my-community-dev-uploads"
  S3_REGION: "ap-northeast-2"
  ALLOWED_ORIGINS: '["https://my-community.shop", "https://k8s.my-community.shop"]'
  FRONTEND_URL: "https://my-community.shop"
  TRUSTED_PROXIES: '["10.0.1.160", "10.0.1.23", "10.0.1.12"]'
```

주의: base의 configmap.yaml에는 환경 무관 설정만 남기고, 환경별 값은 모두 overlay 패치에 넣습니다. 하지만 Kustomize strategic merge patch는 ConfigMap data를 **merge** (덮어쓰기가 아님)하므로, base에 공통 키를 두고 overlay에서 환경별 키만 패치하면 됩니다.

**Step 5: ingress-patch.yaml 생성**

Dev의 현재 ingress.yaml의 hosts/tls를 그대로 사용하는 패치. 패치 형태가 복잡할 경우 JSON Patch 사용:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: community-ingress
  namespace: app
spec:
  tls:
    - hosts:
        - api.my-community.shop
        - my-community.shop
        - ws.my-community.shop
        - api.k8s.my-community.shop
        - k8s.my-community.shop
        - ws.k8s.my-community.shop
      secretName: community-tls
  rules:
    - host: api.my-community.shop
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: community-api-svc
                port:
                  number: 8000
    - host: api.k8s.my-community.shop
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: community-api-svc
                port:
                  number: 8000
    - host: ws.my-community.shop
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: community-ws-svc
                port:
                  number: 8001
    - host: ws.k8s.my-community.shop
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: community-ws-svc
                port:
                  number: 8001
    - host: my-community.shop
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: community-fe-svc
                port:
                  number: 80
    - host: k8s.my-community.shop
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: community-fe-svc
                port:
                  number: 80
```

**Step 6: 검증**

```bash
kubectl kustomize k8s/overlays/dev/ > /dev/null
```

**Step 7: 커밋**

```bash
git add k8s/overlays/dev/
git commit -m "feat(k8s): create Dev Kustomize overlay with MySQL and PV resources"
```

---

### Task 13: Staging overlay 생성

**Files:**
- Create: `k8s/overlays/staging/kustomization.yaml`
- Create: `k8s/overlays/staging/configmap-patch.yaml`
- Create: `k8s/overlays/staging/ingress-patch.yaml`
- Create: `k8s/overlays/staging/db-secret.yaml.example`
- Create: `k8s/overlays/staging/storage/pv-prometheus.yaml`
- Create: `k8s/overlays/staging/storage/pv-redis.yaml`
- Create: `k8s/overlays/staging/storage/pv-uploads.yaml`
- Create: `k8s/overlays/staging/storage/pvc-uploads.yaml`

**Step 1: Staging overlay 디렉토리 생성**

```bash
mkdir -p k8s/overlays/staging/storage
```

**Step 2: kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base
  - storage/pv-prometheus.yaml
  - storage/pv-redis.yaml
  - storage/pv-uploads.yaml
  - storage/pvc-uploads.yaml

patches:
  - path: configmap-patch.yaml
  - path: ingress-patch.yaml

images:
  - name: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-dev-backend-k8s
    newName: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-staging-backend-k8s
    newTag: latest
  - name: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-dev-frontend-k8s
    newName: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-staging-frontend-k8s
    newTag: latest
```

**Step 3: configmap-patch.yaml**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: community-config
  namespace: app
data:
  DB_HOST: "<RDS_ENDPOINT>"
  DB_USER: "admin"
  DB_NAME: "community_service"
  S3_BUCKET_NAME: "my-community-staging-uploads"
  S3_REGION: "ap-northeast-2"
  ALLOWED_ORIGINS: '["https://staging.my-community.shop"]'
  FRONTEND_URL: "https://staging.my-community.shop"
  TRUSTED_PROXIES: '[]'
```

주의: `DB_HOST`는 `terraform apply` 후 RDS 엔드포인트로 교체해야 합니다. `TRUSTED_PROXIES`는 클러스터 배포 후 Worker 노드 IP로 업데이트.

**Step 4: ingress-patch.yaml**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: community-ingress
  namespace: app
spec:
  tls:
    - hosts:
        - staging.my-community.shop
        - api-staging.my-community.shop
        - ws-staging.my-community.shop
      secretName: community-tls-staging
  rules:
    - host: api-staging.my-community.shop
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: community-api-svc
                port:
                  number: 8000
    - host: ws-staging.my-community.shop
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: community-ws-svc
                port:
                  number: 8001
    - host: staging.my-community.shop
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: community-fe-svc
                port:
                  number: 80
```

**Step 5: db-secret.yaml.example (git-tracked 예시)**

```yaml
# 실제 db-secret.yaml은 gitignored — 이 파일을 복사하여 값을 채우세요
apiVersion: v1
kind: Secret
metadata:
  name: community-db-secret
  namespace: app
type: Opaque
stringData:
  DB_PASSWORD: "<RDS_PASSWORD>"
  SECRET_KEY: "<JWT_SECRET_KEY>"
```

**Step 6: PV 파일 생성 (노드 호스트명은 배포 후 수정)**

각 PV 파일은 Dev overlay에서 복사하되:
- `pv-mysql.yaml` 제외 (Staging은 RDS 사용)
- 노드 호스트명(`nodeAffinity`)은 placeholder로 — 클러스터 부트스트랩 후 교체

```yaml
# k8s/overlays/staging/storage/pv-prometheus.yaml (예시)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /data/prometheus
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - "<STAGING_WORKER_HOSTNAME>"
```

pv-redis.yaml, pv-uploads.yaml, pvc-uploads.yaml도 동일 패턴.

**Step 7: .gitignore에 db-secret.yaml 추가**

```bash
echo "k8s/overlays/*/db-secret.yaml" >> .gitignore
```

**Step 8: 검증**

```bash
kubectl kustomize k8s/overlays/staging/ > /dev/null
```

**Step 9: 커밋**

```bash
git add k8s/overlays/staging/ .gitignore
git commit -m "feat(k8s): create Staging Kustomize overlay with RDS and staging domains"
```

---

### Task 14: Prod overlay 생성

**Files:**
- Create: `k8s/overlays/prod/` (Staging 복사 후 도메인/이미지 수정)

**Step 1: Staging overlay 복사**

```bash
cp -r k8s/overlays/staging k8s/overlays/prod
```

**Step 2: kustomization.yaml — 이미지 태그 수정**

```yaml
images:
  - name: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-dev-backend-k8s
    newName: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-prod-backend-k8s
    newTag: latest
  - name: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-dev-frontend-k8s
    newName: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-prod-frontend-k8s
    newTag: latest
```

**Step 3: configmap-patch.yaml — Prod 값**

```yaml
data:
  DB_HOST: "<PROD_RDS_ENDPOINT>"
  DB_USER: "admin"
  S3_BUCKET_NAME: "my-community-prod-uploads"
  ALLOWED_ORIGINS: '["https://my-community.shop"]'
  FRONTEND_URL: "https://my-community.shop"
```

**Step 4: ingress-patch.yaml — Prod 도메인**

TLS hosts: `my-community.shop`, `api.my-community.shop`, `ws.my-community.shop`
secretName: `community-tls-prod`

**Step 5: 검증 + 커밋**

```bash
kubectl kustomize k8s/overlays/prod/ > /dev/null
git add k8s/overlays/prod/
git commit -m "feat(k8s): create Prod Kustomize overlay with production domains"
```

---

### Task 15: Helm values 환경 분기

**Files:**
- Create: `k8s/helm-values/kube-prometheus-stack-dev.yaml`
- Create: `k8s/helm-values/kube-prometheus-stack-staging.yaml`
- Create: `k8s/helm-values/kube-prometheus-stack-prod.yaml`
- Modify: `k8s/helm-values/kube-prometheus-stack.yaml` (Grafana 도메인 제거 → 환경 파일로)

**Step 1: 기존 kube-prometheus-stack.yaml에서 Grafana 호스트 추출**

Grafana Ingress 관련 설정만 환경별 파일로 분리:

`k8s/helm-values/kube-prometheus-stack-dev.yaml`:
```yaml
grafana:
  ingress:
    hosts:
      - grafana.k8s.my-community.shop
    tls:
      - secretName: grafana-tls
        hosts:
          - grafana.k8s.my-community.shop
```

`k8s/helm-values/kube-prometheus-stack-staging.yaml`:
```yaml
grafana:
  ingress:
    hosts:
      - grafana-staging.my-community.shop
    tls:
      - secretName: grafana-tls-staging
        hosts:
          - grafana-staging.my-community.shop
```

`k8s/helm-values/kube-prometheus-stack-prod.yaml`:
```yaml
grafana:
  ingress:
    hosts:
      - grafana.my-community.shop
    tls:
      - secretName: grafana-tls-prod
        hosts:
          - grafana.my-community.shop
```

**Step 2: 기존 파일에서 Grafana 호스트 제거**

`k8s/helm-values/kube-prometheus-stack.yaml`에서 `grafana.ingress.hosts`와 `grafana.ingress.tls` 제거.

**Step 3: 커밋**

```bash
git add k8s/helm-values/
git commit -m "feat(k8s): split Helm Grafana config into per-environment values files"
```

---

### Task 16: 기존 k8s/ 정리 — 레거시 파일 제거

**Files:**
- Delete: `k8s/app/` (base/로 이동 완료)
- Delete: `k8s/cert/` (base/로 이동 완료)
- Delete: `k8s/network/` (base/로 이동 완료)
- Delete: `k8s/storage/` (base/ + overlays/로 이동 완료)
- Delete: `k8s/namespaces.yaml` (base/로 이동 완료)

**Step 1: 이동 완료 확인 후 기존 파일 삭제**

```bash
# 기존 디렉토리 삭제 (base/와 overlays/에 복사 완료된 것 확인 후)
rm -rf k8s/app k8s/cert k8s/network k8s/storage k8s/namespaces.yaml
```

**Step 2: 최종 구조 확인**

```bash
find k8s/ -type f | sort
```

Expected:
```
k8s/base/...
k8s/overlays/dev/...
k8s/overlays/staging/...
k8s/overlays/prod/...
k8s/helm-values/...
```

**Step 3: 커밋**

```bash
git add -A k8s/
git commit -m "refactor(k8s): remove legacy flat structure, Kustomize base/overlay now canonical"
```

---

## Phase 4: Staging 클러스터 부트스트랩

### Task 17: Terraform apply (Staging)

**주의: 실제 AWS 비용 발생. EC2 6대 + RDS + VPC + NAT 등.**

**Step 1: SSH 키 페어 생성 (AWS Console 또는 CLI)**

```bash
aws ec2 create-key-pair --key-name k8s-staging-key --query 'KeyMaterial' --output text > ~/.ssh/k8s-staging-key.pem
chmod 400 ~/.ssh/k8s-staging-key.pem
```

**Step 2: secret.tfvars 작성**

```hcl
db_password           = "<STAGING_DB_PASSWORD>"
k8s_ssh_key_name      = "k8s-staging-key"
k8s_allowed_ssh_cidrs = ["<YOUR_IP>/32"]
bastion_ssh_public_key = ""
```

**Step 3: Terraform init + apply**

```bash
cd environments/staging
terraform init
terraform apply -var-file=terraform.tfvars -var-file=secret.tfvars
```

**Step 4: 출력 기록**

```bash
terraform output k8s_master_public_ips
terraform output k8s_worker_public_ips
terraform output k8s_haproxy_public_ip
terraform output rds_endpoint
```

---

### Task 18: kubeadm HA 부트스트랩

**Step 1: HAProxy 확인**

```bash
ssh -i ~/.ssh/k8s-staging-key ec2-user@<HAPROXY_EIP>
sudo systemctl status haproxy
```

**Step 2: Master 1 초기화**

```bash
ssh -i ~/.ssh/k8s-staging-key ec2-user@<MASTER_1_EIP>
sudo kubeadm init \
  --control-plane-endpoint "<HAPROXY_PRIVATE_IP>:6443" \
  --upload-certs \
  --pod-network-cidr 192.168.0.0/16 \
  --kubernetes-version v1.35.0

mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

기록: `--token`, `--discovery-token-ca-cert-hash`, `--certificate-key`

**Step 3: Master 2, 3 합류**

```bash
# Master 2, 3 각각
ssh -i ~/.ssh/k8s-staging-key ec2-user@<MASTER_N_EIP>
sudo kubeadm join <HAPROXY_PRIVATE_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <CERT_KEY>
```

**Step 4: Worker 1, 2 합류**

```bash
ssh -i ~/.ssh/k8s-staging-key ec2-user@<WORKER_N_IP>
sudo kubeadm join <HAPROXY_PRIVATE_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

**Step 5: 노드 확인**

```bash
kubectl get nodes
```

Expected: 5 nodes (3 master, 2 worker), STATUS=NotReady (CNI 미설치)

---

### Task 19: CNI + Helm 차트 설치

**Step 1: Calico CNI**

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/calico.yaml
kubectl get nodes  # 잠시 후 STATUS=Ready
```

**Step 2: Helm 설치 + 차트**

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

# cert-manager CRDs + chart
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.1/cert-manager.crds.yaml
helm install cert-manager jetstack/cert-manager -f k8s/helm-values/cert-manager.yaml -n cert-manager --create-namespace

# ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx -f k8s/helm-values/ingress-nginx.yaml -n ingress-system --create-namespace

# Redis
helm install redis bitnami/redis -f k8s/helm-values/redis.yaml -n data --create-namespace

# Prometheus + Grafana
helm install prometheus prometheus-community/kube-prometheus-stack \
  -f k8s/helm-values/kube-prometheus-stack.yaml \
  -f k8s/helm-values/kube-prometheus-stack-staging.yaml \
  -n monitoring --create-namespace

# metrics-server
helm install metrics-server metrics-server/metrics-server -f k8s/helm-values/metrics-server.yaml -n kube-system
```

---

### Task 20: Kustomize overlay 적용 + 검증

**Step 1: PV 파일 노드 호스트명 업데이트**

```bash
kubectl get nodes -o wide  # INTERNAL-DNS 컬럼에서 호스트명 확인
```

`k8s/overlays/staging/storage/pv-*.yaml`의 `<STAGING_WORKER_HOSTNAME>` 교체.

**Step 2: ConfigMap의 RDS 엔드포인트 업데이트**

```bash
terraform output rds_endpoint  # Staging에서
```

`k8s/overlays/staging/configmap-patch.yaml`의 `<RDS_ENDPOINT>` 교체.

**Step 3: Secret 적용**

```bash
cp k8s/overlays/staging/db-secret.yaml.example k8s/overlays/staging/db-secret.yaml
# db-secret.yaml에 실제 RDS 비밀번호, JWT Secret Key 입력
kubectl apply -f k8s/overlays/staging/db-secret.yaml
```

**Step 4: Kustomize 적용**

```bash
kubectl apply -k k8s/overlays/staging/
```

**Step 5: 검증**

```bash
kubectl get pods -n app
kubectl get pods -n data
kubectl get pods -n monitoring
kubectl get ingress -n app
```

**Step 6: DNS + TLS 확인**

```bash
dig staging.my-community.shop
curl -s -o /dev/null -w "%{http_code}" https://api-staging.my-community.shop/health
```

**Step 7: 커밋 (노드 호스트명, RDS 엔드포인트 반영)**

```bash
git add k8s/overlays/staging/
git commit -m "feat(k8s): update staging overlay with actual node hostnames and RDS endpoint"
```

---

## Phase 5: CI/CD 환경 확장

### Task 21: BE deploy-k8s.yml 환경 확장

**Files:**
- Modify: `2-cho-community-be/.github/workflows/deploy-k8s.yml`

**Step 1: environment 입력에 staging/prod 추가**

```yaml
inputs:
  environment:
    description: 'Deploy environment'
    required: true
    type: choice
    options:
      - dev
      - staging
      - prod
```

**Step 2: Health check URL 동적 분기**

deploy job의 health check 전에 도메인 설정:

```yaml
- name: Set health check domain
  run: |
    case "${{ inputs.environment }}" in
      dev)     echo "HEALTH_URL=https://api.my-community.shop/health" >> $GITHUB_ENV ;;
      staging) echo "HEALTH_URL=https://api-staging.my-community.shop/health" >> $GITHUB_ENV ;;
      prod)    echo "HEALTH_URL=https://api.my-community.shop/health" >> $GITHUB_ENV ;;
    esac

# Health check에서 ${HEALTH_URL} 사용
```

**Step 3: 커밋**

```bash
cd 2-cho-community-be
git add .github/workflows/deploy-k8s.yml
git commit -m "feat(ci): add staging/prod environment options to K8s deploy workflow"
```

---

### Task 22: FE deploy-k8s.yml 환경 확장

**Files:**
- Modify: `2-cho-community-fe/.github/workflows/deploy-k8s.yml`

동일한 패턴으로 environment 확장 + health check URL 분기.

FE health check 도메인:
```bash
case "${{ inputs.environment }}" in
  dev)     echo "HEALTH_URL=https://my-community.shop" >> $GITHUB_ENV ;;
  staging) echo "HEALTH_URL=https://staging.my-community.shop" >> $GITHUB_ENV ;;
  prod)    echo "HEALTH_URL=https://my-community.shop" >> $GITHUB_ENV ;;
esac
```

**커밋:**

```bash
cd 2-cho-community-fe
git add .github/workflows/deploy-k8s.yml
git commit -m "feat(ci): add staging/prod environment options to K8s deploy workflow"
```

---

### Task 23: GitHub Environment + Secrets 설정

**수동 작업 (GitHub UI 또는 gh CLI)**

**Step 1: BE repo — GitHub Environments 생성**

```bash
# staging
gh api repos/<owner>/2-cho-community-be/environments/staging -X PUT

# prod (with required reviewers)
gh api repos/<owner>/2-cho-community-be/environments/prod -X PUT \
  -f 'reviewers[][type]=User' -f 'reviewers[][id]=<YOUR_USER_ID>'
```

**Step 2: Environment Secrets 설정 (staging)**

```bash
gh secret set K8S_MASTER_HOST --env staging --body "<STAGING_MASTER_1_EIP>"
gh secret set K8S_MASTER_SSH_KEY --env staging < ~/.ssh/k8s-staging-key.pem
gh secret set K8S_SSH_SG_ID --env staging --body "<STAGING_SSH_SG_ID>"
```

**Step 3: FE repo도 동일하게 설정**

---

## Phase 6: Prod 환경

### Task 24: Prod Terraform 구성

Dev의 Task 8-9와 동일한 패턴으로 `environments/prod/` 재작성.

**핵심 차이:**
- `backend.key = "prod/terraform.tfstate"`
- `vpc_cidr = "10.2.0.0/16"`
- `single_nat_gateway = false` (Dual NAT)
- RDS: `db.t3.medium`, Multi-AZ, 14일 백업, deletion_protection
- K8s: `master_count=3, haproxy_enabled=true`
- DNS: `"", "api", "ws", "grafana"` (메인 도메인)
- `admin_username = "admin"`, `create_deployer_role = true`

**커밋:**

```bash
git add environments/prod/
git commit -m "feat(prod): rewrite Terraform config for K8s + RDS HA architecture"
```

---

### Task 25: Prod Terraform apply + kubeadm 부트스트랩

Task 17-20과 동일한 절차. SSH 키는 `k8s-prod-key`.

---

### Task 26: Prod CI/CD Secrets 설정 + 배포 테스트

Task 23과 동일. Prod environment에 required reviewers 설정.

---

## Phase 7: 정리

### Task 27: Lambda 모듈 정리

**Files:**
- Modify: `modules/` 디렉토리 — Lambda 전용 모듈에 deprecation 주석 추가

Lambda 모듈(lambda, api_gateway, cloudfront, acm_cloudfront, lambda_websocket, api_gateway_websocket, dynamodb, eventbridge, efs, cloudwatch)은 어떤 환경에서도 사용하지 않으므로 deprecation 표기. 즉시 삭제하지 않고 참고용으로 보존 (필요시 추후 삭제).

```bash
# 각 모듈의 variables.tf 헤더에 주석 추가
# DEPRECATED: Lambda 아키텍처 모듈. K8s 전환 완료 (2026-03). 참고용으로 보존.
```

**커밋:**

```bash
git commit -am "chore: mark Lambda-era modules as deprecated"
```

---

### Task 28: 문서 업데이트

**Files:**
- Modify: `README.md` — 환경 비교 테이블, 비용 정보, 부트스트랩 절차
- Modify: `CHANGELOG.md` — Phase 1-7 기록
- Modify: `report.md` — HA 아키텍처 반영
- Modify: `/Users/revenantonthemission/my-community/CLAUDE.md` — 신규 gotchas, 환경 정보

**커밋:**

```bash
git commit -am "docs: update all documentation for K8s unified architecture"
```

---

## 태스크 요약

| Phase | Task | 설명 | 예상 시간 |
|-------|------|------|-----------|
| 1 | 1-6 | k8s_ec2 모듈 확장 + Dev state mv | 2-3시간 |
| 2 | 7-10 | Staging Terraform 구성 + plan 검증 | 1-2시간 |
| 3 | 11-16 | Kustomize base/overlay 전환 | 2-3시간 |
| 4 | 17-20 | Staging 클러스터 부트스트랩 | 2-3시간 |
| 5 | 21-23 | CI/CD 환경 확장 | 1시간 |
| 6 | 24-26 | Prod 환경 (Staging 반복) | 2-3시간 |
| 7 | 27-28 | 정리 + 문서 | 1시간 |
| | **합계** | | **11-16시간** |
