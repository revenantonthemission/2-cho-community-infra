# K8s 통합 아키텍처 설계 — Staging/Prod 마이그레이션

> **작성일**: 2026-03-14
> **상태**: 승인됨
> **선행 문서**: `2026-03-10-k8s-migration-design.md` (원본 설계), `2026-03-12-k8s-implementation-design.md` (Dev 구현)

## 배경

Dev 환경의 K8s 마이그레이션이 완료되었고 (2026-03-14 Lambda 제거), 이제 Staging/Prod도 K8s로 통합합니다. Staging/Prod의 Lambda 인프라는 Terraform 코드만 존재하고 실제 apply된 적이 없으므로, clean rewrite가 가능합니다.

## 결정 사항

| 항목 | 결정 |
|------|------|
| 아키텍처 | 모든 환경 K8s (kubeadm on EC2) |
| Staging 도메인 | `*-staging.my-community.shop` (staging, api-staging, ws-staging, grafana-staging) |
| 인스턴스 타입 | 전 환경 `c7i-flex.large` |
| Prod 구성 | Master 3 + Worker 2 (HA 컨트롤 플레인) |
| Staging 구성 | Master 3 + Worker 2 (Prod 미러링) |
| 배포 순서 | Staging 먼저 → 검증 후 Prod |
| 데이터베이스 | RDS 유지 (K8s 앱 → RDS 엔드포인트) |
| HA 로드밸런서 | HAProxy on EC2 (t3.micro, ~$8/월) |
| Redis | K8s 내부 Helm (Dev와 동일) |
| SSH 키 | 환경별 분리 (k8s-staging-key, k8s-prod-key) |

## 1. k8s_ec2 모듈 확장

기존 `modules/k8s_ec2/`를 HA 지원으로 확장합니다 (Option 1: 단일 모듈).

### 신규 변수

```hcl
variable "master_count" {
  description = "Master 노드 수 (1=단일, 3=HA)"
  type        = number
  default     = 1
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

### 리소스 변경

- `aws_instance.master`: 단일 → `count = var.master_count`
- `aws_eip.master`: 단일 → `count = var.master_count`
- `aws_instance.worker`: `count = 2` → `count = var.worker_count`
- Worker EBS: 하드코딩 → `worker_volume_sizes` 리스트 인덱싱
- `aws_instance.haproxy`: 신규, `count = var.haproxy_enabled ? 1 : 0`
- `aws_eip.haproxy`: 신규, 조건부

### Security Group 추가

```hcl
# k8s_haproxy SG (조건부)
- 6443 ingress: allowed_ssh_cidrs + k8s_internal SG
- 9000 ingress: allowed_ssh_cidrs (HAProxy stats)
- egress: all
```

Master SG의 6443 ingress에 HAProxy SG 추가.

### Outputs 변경

```hcl
# 단수 → 복수
master_public_ip  → master_public_ips  (list)
master_private_ip → master_private_ips (list)

# 신규
haproxy_public_ip   (nullable)
haproxy_private_ip  (nullable)
k8s_internal_sg_id  (RDS SG 연동용)
```

### Dev 환경 state migration

`aws_instance.master` → `aws_instance.master[0]` 주소 변경으로 `terraform state mv` 필요:

```bash
terraform state mv 'module.k8s_ec2[0].aws_instance.master' 'module.k8s_ec2[0].aws_instance.master[0]'
terraform state mv 'module.k8s_ec2[0].aws_eip.master' 'module.k8s_ec2[0].aws_eip.master[0]'
```

## 2. 환경별 Terraform 구성

### Staging main.tf 모듈 구성

| Module | 역할 |
|--------|------|
| iam | IAM 사용자/그룹 |
| vpc | VPC 10.1.0.0/16, single NAT |
| s3 | uploads + CloudTrail logs |
| route53 | DNS 존 조회 |
| acm | api-staging 도메인 인증서 |
| ses | 이메일 발송 |
| ecr | 컨테이너 이미지 저장소 |
| rds | MySQL (db.t3.small, 단일 AZ) |
| ec2 (bastion) | 비활성화 |
| cloudtrail | 감사 로그 |
| k8s_ec2 | Master 3 + Worker 2 + HAProxy |

Lambda 관련 모듈 제거: efs, lambda, api_gateway, cloudwatch, cloudfront, acm_cloudfront, dynamodb, eventbridge, lambda_websocket, api_gateway_websocket

### K8s 모듈 설정

```hcl
# Staging
module "k8s_ec2" {
  master_count          = 3
  worker_count          = 2
  haproxy_enabled       = true
  haproxy_instance_type = "t3.micro"
}

# Dev (기존 유지)
module "k8s_ec2" {
  master_count    = 1      # 기본값
  worker_count    = 2      # 기본값
  haproxy_enabled = false  # 기본값
}
```

### RDS ← K8s SG 연동

```hcl
resource "aws_security_group_rule" "rds_from_k8s" {
  count                    = var.create_k8s_cluster ? 1 : 0
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = module.vpc.rds_security_group_id
  source_security_group_id = module.k8s_ec2[0].k8s_internal_sg_id
}
```

### DNS Records

```hcl
# Staging
for_each = ["staging", "api-staging", "ws-staging", "grafana-staging"]
# → staging.my-community.shop, api-staging.my-community.shop, etc.

# Prod
for_each = ["", "api", "ws", "grafana"]
# → my-community.shop, api.my-community.shop, etc.
```

### Prod 차이점

| 설정 | Staging | Prod |
|------|---------|------|
| RDS 인스턴스 | db.t3.small | db.t3.medium |
| RDS Multi-AZ | false | true |
| RDS 백업 보존 | 3일 | 14일 |
| RDS 삭제 보호 | false | true |
| NAT Gateway | Single | Dual |
| 도메인 | *-staging.my-community.shop | *.my-community.shop |

### 환경 비교

| 설정 | Dev | Staging | Prod |
|------|-----|---------|------|
| Master | 1 | 3 (HA) | 3 (HA) |
| Worker | 2 | 2 | 2 |
| HAProxy | 없음 | t3.micro | t3.micro |
| DB | K8s MySQL | RDS db.t3.small | RDS db.t3.medium |
| RDS Multi-AZ | N/A | No | Yes |
| NAT Gateway | Single | Single | Dual |
| 도메인 | *.my-community.shop | *-staging.my-community.shop | *.my-community.shop |
| 월 비용 | ~$224 | ~$390 | ~$498 |

## 3. K8s 매니페스트 Kustomize 전환

### 디렉토리 구조

```
k8s/
├── base/                          # 환경 공통
│   ├── kustomization.yaml
│   ├── app/                       # 현재 k8s/app/ → base/app/
│   │   ├── api-deployment.yaml
│   │   ├── api-hpa.yaml
│   │   ├── api-service.yaml
│   │   ├── api-servicemonitor.yaml
│   │   ├── configmap.yaml         # 공통값만
│   │   ├── cronjob-ecr-refresh.yaml
│   │   ├── cronjob-feed-recompute.yaml
│   │   ├── cronjob-token-cleanup.yaml
│   │   ├── fe-deployment.yaml
│   │   ├── fe-service.yaml
│   │   ├── ingress.yaml           # 도메인 placeholder
│   │   ├── networkpolicy.yaml
│   │   └── ws-deployment.yaml
│   ├── cert/
│   │   └── clusterissuer.yaml
│   ├── network/
│   │   └── networkpolicy-data.yaml
│   ├── storage/
│   │   └── storageclass.yaml
│   └── namespaces.yaml
│
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   ├── configmap-patch.yaml   # DB_HOST=mysql.data.svc, S3=dev bucket
│   │   ├── ingress-patch.yaml     # *.my-community.shop + *.k8s.my-community.shop
│   │   ├── mysql.yaml             # Dev만: K8s 내부 MySQL
│   │   ├── cronjob-mysql-backup.yaml
│   │   └── storage/               # Dev PV (노드 호스트명)
│   │       ├── pv-mysql.yaml
│   │       ├── pv-prometheus.yaml
│   │       ├── pv-redis.yaml
│   │       └── pv-uploads.yaml
│   │
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   ├── configmap-patch.yaml   # DB_HOST=RDS, S3=staging bucket
│   │   ├── ingress-patch.yaml     # *-staging.my-community.shop
│   │   ├── db-secret.yaml         # RDS 자격증명 (gitignored)
│   │   └── storage/
│   │       ├── pv-prometheus.yaml
│   │       ├── pv-redis.yaml
│   │       └── pv-uploads.yaml    # MySQL PV 불필요
│   │
│   └── prod/
│       ├── kustomization.yaml
│       ├── configmap-patch.yaml   # DB_HOST=RDS, S3=prod bucket
│       ├── ingress-patch.yaml     # *.my-community.shop (apex)
│       ├── db-secret.yaml         # RDS 자격증명 (gitignored)
│       └── storage/
│           ├── pv-prometheus.yaml
│           ├── pv-redis.yaml
│           └── pv-uploads.yaml
│
└── helm-values/
    ├── cert-manager.yaml
    ├── ingress-nginx.yaml
    ├── kube-prometheus-stack.yaml              # 공통
    ├── kube-prometheus-stack-dev.yaml          # grafana.k8s.my-community.shop
    ├── kube-prometheus-stack-staging.yaml      # grafana-staging.my-community.shop
    ├── kube-prometheus-stack-prod.yaml         # grafana.my-community.shop
    ├── metrics-server.yaml
    └── redis.yaml
```

### Kustomize 이미지 오버라이드

```yaml
# overlays/staging/kustomization.yaml
images:
  - name: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-dev-backend-k8s
    newName: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-staging-backend-k8s
    newTag: latest
  - name: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-dev-frontend-k8s
    newName: 559352512800.dkr.ecr.ap-northeast-2.amazonaws.com/my-community-staging-frontend-k8s
    newTag: latest
```

### DB Secret (Staging/Prod, gitignored)

```yaml
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

Deployment에서 `envFrom: [{secretRef: {name: community-db-secret}}]`로 주입.

### 배포 명령어

```bash
kubectl apply -k k8s/overlays/dev/       # Dev
kubectl apply -k k8s/overlays/staging/   # Staging
kubectl apply -k k8s/overlays/prod/      # Prod
```

## 4. CI/CD 파이프라인 환경 분기

### 워크플로우 변경 (BE/FE 공통)

```yaml
inputs:
  environment:
    options: [dev, staging, prod]   # staging, prod 추가
```

이미지 경로는 `ENV` 변수로 자동 분기:
- `my-community-dev-backend-k8s`
- `my-community-staging-backend-k8s`
- `my-community-prod-backend-k8s`

### GitHub Environment Secrets

| Secret | Dev | Staging | Prod |
|--------|-----|---------|------|
| K8S_MASTER_HOST | Master EIP | Master 1 EIP | Master 1 EIP |
| K8S_MASTER_SSH_KEY | dev 키 | staging 키 | prod 키 |
| K8S_SSH_SG_ID | dev SG ID | staging SG ID | prod SG ID |

### Health Check URL 동적 분기

```bash
case "${ENV}" in
  dev)     API_DOMAIN="api.my-community.shop"; FE_DOMAIN="my-community.shop" ;;
  staging) API_DOMAIN="api-staging.my-community.shop"; FE_DOMAIN="staging.my-community.shop" ;;
  prod)    API_DOMAIN="api.my-community.shop"; FE_DOMAIN="my-community.shop" ;;
esac
```

### Prod 배포 보호

GitHub Environment 설정:
- **prod**: Required reviewers, `main` 브랜치만 허용
- **staging/dev**: 제한 없음

## 5. HAProxy 구성 및 kubeadm HA 부트스트랩

### HAProxy 설정

```
frontend k8s_api → bind *:6443
backend k8s_masters → roundrobin, health check /healthz (check-ssl verify none)
frontend stats → bind *:9000, mode http
```

- TCP 모드 (L4), TLS 패스스루
- Master 다운 시 자동 제외, 복구 시 자동 복귀

### 부트스트랩 순서

1. **HAProxy 확인**: user_data로 자동 구성, `systemctl status haproxy`
2. **Master 1 초기화**: `kubeadm init --control-plane-endpoint <HAPROXY_PRIVATE_IP>:6443 --upload-certs --pod-network-cidr 192.168.0.0/16`
3. **Master 2, 3 합류**: `kubeadm join --control-plane --certificate-key <KEY>`
4. **Worker 1, 2 합류**: `kubeadm join`
5. **CNI + Helm**: Calico, ingress-nginx, cert-manager, redis, kube-prometheus-stack, metrics-server
6. **Kustomize 적용**: `kubectl apply -f db-secret.yaml` → `kubectl apply -k overlays/staging/`

### 인증서 관리

- kubeadm 인증서: 1년 주기 갱신 (`kubeadm certs renew all`, 모든 Master)
- TLS 인증서: cert-manager + Let's Encrypt 자동 갱신

## 6. 비용 요약

| 환경 | 월 비용 |
|------|---------|
| Dev | ~$224 |
| Staging | ~$390 |
| Prod | ~$498 |
| **합계** | **~$1,112** |

비용 절감 옵션: Staging 미사용 시 EC2 중지 (~$300/월 절감), Reserved Instances (~30% 절감)

## 7. 구현 순서

1. **Phase 1**: k8s_ec2 모듈 확장 + Dev state mv
2. **Phase 2**: Staging Terraform (main.tf 재작성 + apply)
3. **Phase 3**: Kustomize 전환 (base/overlay 구조)
4. **Phase 4**: Staging 클러스터 부트스트랩 + 검증
5. **Phase 5**: CI/CD 환경 확장
6. **Phase 6**: Prod 환경 (Staging 검증 후)
7. **Phase 7**: 정리 (Lambda 코드 제거, 문서 업데이트)

## 리스크

| 리스크 | 대응 |
|--------|------|
| Dev state mv 실패 | terraform plan으로 사전 확인 |
| kubeadm 인증서 키 10분 만료 | Master 3대 join을 빠르게 연속 실행 |
| RDS ↔ K8s 통신 | VPC 내부, SG 규칙만 추가 |
| HAProxy SPOF | 단기 허용, EC2 재시작으로 복구 |
| Staging TLS 발급 실패 | DNS 전파 확인 후 재시도 |
