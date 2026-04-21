# Infrastructure — CLAUDE.md

Terraform (AWS) + K8s (kubeadm) + GitHub Actions CI/CD. 상세 아키텍처는 `README.md`, `report.md` 참조.

## Commands

```bash
# Terraform (환경 디렉토리에서 실행)
cd environments/staging  # 또는 environments/prod
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
terraform plan -var-file=terraform.tfvars -var-file=secret.tfvars  # 민감 변수

# K8s 매니페스트 검증 (CRD 리소스 에러는 정상)
kubectl apply --dry-run=client -k k8s/overlays/staging/ 2>&1  # 또는 prod
```

## Terraform 구조

- **활성 모듈**: `modules/` (13개: stack, iam, vpc, s3, route53, acm, ses, ecr, rds, cloudtrail, k8s_ec2, eks, tfstate). `stack`은 9개 공통 모듈의 composition module. `tfstate`는 bootstrap 전용
- **레거시 모듈**: 삭제 완료 (2026-03-16~19). git history에 보존. 10개: ec2, efs, lambda, api_gateway, cloudwatch, cloudfront, dynamodb, api_gateway_websocket, lambda_websocket, eventbridge
- **환경**: `environments/{bootstrap,staging,prod}`. dev는 로컬 docker-compose로 전환 (2026-03-25)
- **상태 저장**: S3 + DynamoDB 원격 백엔드. bootstrap만 로컬 상태
- **Provider lock**: `.terraform.lock.hcl`은 git 추적. `terraform init -upgrade` 후 lock 파일 변경도 커밋
- **AWS 리전**: ap-northeast-2 (서울)
- **도메인**: my-community.shop (Route 53, ACM SSL)

## K8s 마이그레이션 (개발 환경)

- **설계**: `docs/plans/2026-03-10-k8s-migration-design.md` (원본), `docs/plans/2026-03-12-k8s-implementation-design.md` (Phase별 상세)
- **상태**: Prod EKS 배포 완료 (NLB + Managed Node Group). Staging kubeadm 배포 완료 (1M+2W). Dev 환경은 로컬 docker-compose로 전환 (2026-03-25)
- **RDS 접근**: K8s Worker에서 직접 접근 (접착 리소스 `rds_from_k8s` SG 규칙)
- **매니페스트**: `k8s/` (Kustomize base/overlay. ArgoCD가 `k8s/overlays/{env}/` 자동 sync)
- **Terraform 모듈**: `modules/k8s_ec2/`
- **ArgoCD**: `k8s/argocd/` (install/, projects/, config/, app-of-apps/, root-app.yaml)

### ArgoCD

- **설치**: Helm (`argo/argo-cd`), `k8s/argocd/install/helm-values.yaml`. argocd 네임스페이스
- **App-of-Apps**: `root-app.yaml` → `app-of-apps/{env}/app-community.yaml` → `overlays/{env}/`
- **소스 저장소**: fork repo (`revenantonthemission/2-cho-community-infra`)
- **SSO**: GitHub OAuth App + Dex (개인 계정, orgs 필터 없음). RBAC에서 사용자명 직접 매핑
- **Secrets**: `argocd-secret` (Dex OAuth, 수동), `community-secrets` (ESO → Secrets Manager 자동 동기화)
- **Webhook**: fork infra repo → `https://argocd.my-community.shop/api/webhook` (즉시 sync)
- **CD 흐름**: CI(`deploy-k8s.yml`) → ECR push → `kustomize edit set image` → fork infra repo에 태그 커밋 → ArgoCD 자동 sync
- **UI**: `https://argocd.my-community.shop`
- **retry 실패 시**: AppProject 변경 후 sync 재시도 필요. `kubectl patch application <name> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'`
- **argocd 네임스페이스 부트스트랩**: `kubectl apply -f k8s/argocd/install/namespace.yaml` (base/namespaces.yaml에 없음)
- **AppProject clusterResourceWhitelist**: Namespace, PV, StorageClass, ClusterIssuer 허용 필요 (overlay가 클러스터 범위 리소스 포함)

### K8s Gotchas

- **API 프로브 분리**: readinessProbe → `/readyz` (DB 503), livenessProbe → `/livez` (DB 무관), startupProbe → `/livez` (초기 시작 대기). `/health`는 하위 호환 (503 반환). liveness에 DB 체크 포함 시 장애 재시작 루프. startupProbe가 성공할 때까지 liveness/readiness 비활성화
- **preStop hook**: `sleep 5` — endpoint 제거 전파 대기. 미설정 시 롤링 배포 502
- **BE 구조 변경**: `modules/` + `core/` 모듈러 모놀리스. 구 디렉토리(controllers/, models/, services/) 삭제됨. Dockerfile은 `COPY . .`이므로 영향 없음
- **SSH 접속 불가**: `k8s_allowed_ssh_cidrs`에 현재 IP 확인. `curl -s https://checkip.amazonaws.com`
- **hostNetwork Ingress + NetworkPolicy**: `namespaceSelector` 매칭 안 됨. `ipBlock`으로 VPC CIDR(`10.0.0.0/16`) 허용
- **metrics-server on kubeadm**: `--kubelet-insecure-tls` 플래그 필수
- **Cross-platform Docker 빌드**: Mac(ARM64) → EC2(x86_64): `docker build --platform linux/amd64` 필수
- **MySQL 9.x `character-set-client-handshake` 제거됨**: `init_connect='SET NAMES utf8mb4'`로 대체
- **AWS Free Tier EIP 한도**: 리전당 5개. HA 클러스터는 한도 초과
- **c7i-flex.large AZ 제한**: ap-northeast-2a 미지원, 2b/2d만
- **K8s base 이미지 placeholder 패턴**: base deployment는 `community-backend:latest`, `community-frontend:latest` 사용. 각 overlay의 `images` transformer가 ECR URI로 치환
- **ECR CronJob Account ID**: `aws sts get-caller-identity`로 동적 조회. 하드코딩 금지
- **ACPI Power Button 방어**: 모든 노드에 `HandlePowerKey=ignore` 설정됨 (`/etc/systemd/logind.conf.d/99-ignore-power-key.conf`). AMI 재생성 시 포함 필수. 미설정 시 AWS 유지보수 이벤트로 예기치 않은 셧다운 발생
- **Worker 노드 원격 명령**: Master→Worker SSH 불가 (키 미공유). `AWS_PROFILE=mfa aws ssm send-command --instance-ids <id> --document-name AWS-RunShellScript --parameters 'commands=[...]'` 사용
- **SSM send-command JSON 이스케이프**: 셸 파라미터로 JSON 전달 시 이스케이프 깨짐. heredoc으로 `/tmp/파일.json` 작성 후 `--patch-file` 참조
- **Staging 노드 토폴로지 라벨**: EC2 재시작 후 `topology.kubernetes.io/zone` 라벨 수동 적용 필요. 미적용 시 TopologySpreadConstraints로 Pod Pending. `kubectl label node <name> topology.kubernetes.io/zone=ap-northeast-2b --overwrite`
- **배포 i/o timeout 진단**: Master EC2 상태 확인 → stopped면 `aws ec2 start-instances`. 원인 분석은 `journalctl -b -1`에서 `Power key pressed` 검색
- **kubeadm init EIP hairpin NAT**: `--control-plane-endpoint`에 EIP 사용 불가 (AWS hairpin NAT 미지원). private IP 사용 + `--apiserver-cert-extra-sans`에 EIP 추가
- **Calico v3.29 natOutgoing 타입 변경**: `natOutgoing: true` → `natOutgoing: Enabled` (boolean → string enum)
- **ArgoCD PreSync hook SA 의존성**: PreSync Job이 메인 sync에서 생성되는 SA를 참조하면 deadlock. SA를 수동 생성하거나 hook에서 default SA 사용
- **RDS 스키마 초기화**: `alembic upgrade head`가 `0001_baseline.py`에서 schema.sql을 자동 실행 (user 테이블 존재 시 건너뜀). 수동 schema.sql 적용 불필요
- **SSM send-command 복잡한 스크립트**: heredoc/JSON 이스케이프가 깨짐. S3 uploads 버킷 경유 파일 전달이 안정적. `TimeoutSeconds` 최소값 30
- **ECR 이미지 pull**: K8s 노드 IAM role로 직접 pull 가능. `ecr-cred` Secret은 CronJob IMDS 우회용

### EKS Prod Gotchas

- **local-storage PV가 topologySpread 차단**: `nodeAffinity`가 AZ 분산을 방해. S3 전환 완료된 PVC는 제거 필수
- **Cluster Autoscaler 버전 매칭**: EKS 1.31에는 CA chart 9.43.x + `image.tag=v1.31.0`. 최신 chart는 DRA API 오류
- **Bitnami Redis Sentinel 서비스명**: `architecture: replication` + sentinel 시 서비스명이 `redis-master` → `redis`로 변경. ConfigMap REDIS_URL 패치 필요
- **ESO API 버전**: 최신 ESO는 `external-secrets.io/v1` (`v1beta1` 아님)
- **Secret 변경 시 Pod 재시작 필요**: K8s Secret은 Pod 생성 시점에 읽힘. `kubectl rollout restart` 필수
- **Alertmanager Slack webhook**: K8s Secret(`slack-webhook`)으로 관리. helm-values에 URL 하드코딩 금지
- **Helm 설치 목록 (Prod)**: cert-manager, ingress-nginx, redis (sentinel), kube-prometheus-stack, prometheus-cloudwatch-exporter, cluster-autoscaler, external-secrets, argocd
- **StatefulSet volumeClaimTemplates immutable**: Helm upgrade로 StorageClass 변경 불가. `kubectl delete statefulset` + `kubectl delete pvc` 후 Helm upgrade로 재생성
- **EBS CSI Driver IRSA 필수**: EKS addon 설치만으로는 동작 안 함. IRSA 없으면 `no EC2 IMDS role found`. Terraform에서 IRSA 생성 후 addon 재설치
- **Prometheus persistence**: Prod에서 emptyDir 사용 중 (EBS CSI IRSA 설정 후 gp2 StorageClass로 전환 필요)
- **Calico IPIP AWS 차단**: kubeadm + Calico에서 `ipipMode: Always` 시 cross-node Pod 트래픽 실패. AWS VPC가 IPIP 프로토콜(4번) 차단. `ipipMode: Never`로 직접 라우팅 전환 필수 (source_dest_check: false 선행)
- **kubeadm ECR CronJob IMDS 문제**: Pod 내 IMDS가 K8s 노드 역할 대신 SSM 역할 반환 → ECR 토큰 획득 실패. 로컬에서 `aws ecr get-login-password` → SSM으로 Secret 주입 (12시간 유효)
- **Staging promote 워크플로우**: `promote.yml`이 staging → prod 순차 배포. prod environment에 Required Reviewers 설정 필요
- **ArgoCD sync window (Staging)**: `staging` AppProject에 deny window (매일 00:00-01:00 KST). `manualSync: false`로 수동 sync도 차단됨. 긴급 배포 시 AppProject에서 `syncWindows` 임시 제거 후 복원
- **ArgoCD force sync + SSA 비호환**: `--force cannot be used with --server-side`. syncOptions에서 `ServerSideApply=true` 제거 후 force sync 실행
- **EKS desired_size 드리프트**: Cluster Autoscaler가 노드를 동적으로 추가/제거하면 `desired_size`가 Terraform 선언값과 달라짐. `terraform plan`에서 변경 표시는 정상. apply 시 CA가 다시 조정
- **Terraform state KMS 암호화**: S3 백엔드에 `kms_key_id` 설정됨. 새 환경 bootstrap 시 KMS 키 ARN 필요. `backend` 블록 변경 후 `terraform init -reconfigure` 필수

### 테스트

- **BE 스모크 테스트**: `pytest tests/smoke/ --base-url=https://api.my-community.shop --no-cov -v`
- **BE Redis 통합 테스트**: `pytest tests/integration/ -m integration --no-cov` (Redis 실행 필요)
- **K8s manifest 검증**: `validate-manifests.yml` (PR/push 시 자동, Kustomize 3환경 + TF validate)
- **CD 스모크 테스트**: BE/FE `deploy-k8s.yml`의 `smoke-test` job (prod 배포 시 자동)

## GitHub Actions CI/CD

### CI
- **백엔드**: `2-cho-community-be/.github/workflows/python-app.yml` (lint + mypy + pytest)
- **MySQL 서비스 컨테이너**: MySQL 9.6으로 스키마 초기화 후 pytest 실행

### CD
- **인프라 배포** (`deploy-infra.yml`): PR → matrix plan + 코멘트 / `workflow_dispatch` → plan 또는 apply
- **K8s 배포** (`deploy-k8s.yml`): ECR push → infra repo 태그 커밋 → ArgoCD 자동 sync

### OIDC & IAM
- **OIDC 인증**: GitHub Actions → AWS STS. `bootstrap/oidc.tf`에서 관리 (계정당 1개 singleton)
- **OIDC provider 절대 삭제 금지**: 삭제 시 모든 CI/CD 인증 실패
- **OIDC 최소 권한**: 서비스별 스코프 정책 (AdministratorAccess 금지)
- **OIDC 배포 범위**: staging은 fork + upstream 모두 허용, prod는 upstream 전용
- **GitHub 설정**: 각 repo에 `AWS_ACCOUNT_ID` variable + Environment secrets 필요
- **Fork PR plan 제한**: fork PR은 environment secrets 접근 불가
- **`workflow_dispatch` 제약**: 워크플로우 파일이 default branch에 존재해야 트리거 가능
- **IAM 사용자 패턴**: OIDC 정책에 `user/my-community-*`와 `user/admin-*` 패턴 모두 필요

## Terraform Gotchas

### 필수 규칙
- **실행 디렉토리**: 반드시 `environments/{env}/`에서 실행
- **민감 정보 커밋 금지**: `secret.tfvars`(gitignored) 또는 `-var` 플래그 사용
- **환경별 `main.tf` 맹목적 복사 금지**: `backend.key`, 헤더 주석, 배포 모듈이 다름. 상태 파일 충돌 → 인프라 파괴 위험
- **점진적 배포**: 모듈 주석 처리 시 `outputs.tf`도 함께 주석 처리
- **순환 참조**: 모듈 간 양방향 참조 불가. "접착" 리소스를 `main.tf`로 추출
- **`count` 제거 주의**: `module.foo[0].*` → `module.foo.*` 변경 → destroy+recreate. `terraform state mv` 선행 필수
- **`CLAUDE.md`/`docs/` gitignored**: 인프라 repo에서 `git add CLAUDE.md` 불가. 로컬 전용 파일

### SSL & Proxy
- **ProxyHeadersMiddleware 필수**: nginx SSL termination 시. 없으면 trailing slash 리다이렉트가 `http://`
- **`trusted_hosts` 보안**: `"*"` 금지. `settings.TRUSTED_PROXIES` 또는 `["127.0.0.1", "::1"]`

### AWS 리소스
- **Free Tier**: `t3.micro` 사용 (`t4g` 아님). NAT Gateway ~$32/월
- **EC2 동적 Public IP**: `map_public_ip_on_launch`로 할당된 IP는 인스턴스 stop 시 해제됨. DNS에 사용하는 노드는 반드시 EIP 할당
- **EC2 `associate_public_ip_address` ForceNew**: 서브넷 자동할당 IP는 state에 `false`로 기록. 코드에 `true` 추가 시 인스턴스 교체 발생 — state rm + import로도 해결 불가 (AWS API가 `false` 반환)
- **ECR repo 삭제**: 이미지가 남아있으면 `force_delete` 없이 Terraform 삭제 실패. AWS CLI로 이미지 선 삭제 필요: `aws ecr batch-delete-image`
- **ECR lifecycle**: `tagStatus=any`는 현재 배포 이미지 삭제 가능. `untagged`/`tagged` 분리
- **AL2023 AMI 최소 볼륨**: 30GB 필요
- **S3 lifecycle + versioning**: `depends_on` 필요
- **SES 도메인 레코드 공유**: 환경 간 공유됨. 한 환경에서만 관리
- **AWS SG descriptions**: ASCII만 허용 (한국어 금지)
- **`data.aws_region.current`**: `.name` deprecated → `.id` 사용

### SSM & IAM
- **SSM 파라미터 추가**: `core/config.py` ssm_mappings + K8s Secret/ConfigMap + IAM 정책 동시 수정
- **SSM IAM 액션**: `ssm:GetParameter`(단일)과 `ssm:GetParameters`(배치)는 별개. 코드는 배치 사용
- **IAM `default_tags` + `iam:CreatePolicy`**: `iam:TagPolicy`도 필요
- **OIDC IAM 정책**: Resource `${var.project}-*` 패턴 제한. `Resource = "*"` 금지
- **IAM 부트스트랩**: 최초 apply는 루트 자격 증명 필수
- **MFA CLI**: `aws sts get-session-token` 후 `[mfa]` 프로필에 임시 자격 증명 저장. Terraform/AWS CLI 실행 시 `AWS_PROFILE=mfa` 필수. `get-caller-identity`는 MFA 없이도 성공하므로 인증 확인 지표로 사용 불가
- **AWS 환경변수 우선순위**: 만료된 환경변수가 credentials 파일보다 우선. `unset` 후 프로필 사용

### 기타
- **Terraform `count` 조건에 ARN 금지**: `bool` 변수 사용
- **SES 배포 순서**: bootstrap apply → env apply
- **Terraform state "already exists"**: `terraform refresh` → 재시도. 안 되면 `state rm` → `import`
- **모듈 제거 시 DNS 연쇄 삭제**: 제거 전 DNS 이전 필수
- **모듈 제거 연쇄 영향**: VPC SG → 환경 main.tf(모듈 블록 + 접착 리소스) + variables.tf + terraform.tfvars + outputs.tf 4곳 × 환경 수. `terraform validate`로 누락 참조 검증
- **RDS 접근 (Bastion 없음)**: `kubectl exec -n app deploy/community-api` 또는 임시 `mariadb:lts` Pod 사용. Worker SG → RDS SG 3306 허용 (`rds_from_k8s` 접착 리소스)
- **`amazon/aws-cli` 이미지**: `mysql`→`mariadb105`, `gzip` 별도 설치

## 아키텍처 문서 동기화

인프라 변경 시 3곳 동시 갱신: `README.md` (모듈·디렉토리·환경표), `report.md` (설계도·HA·장애시나리오), 이 `CLAUDE.md` (gotchas·상태·커맨드). infra 커밋과 docs 커밋을 쌍으로 관리
