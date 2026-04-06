# Changelog

## 2026-03 (Mar)

- **03-31: 인프라 옵저버빌리티 강화** (PR #6)
  - feat: CloudWatch Exporter IRSA 역할 추가
  - feat: CloudWatch Exporter Helm values 추가
  - feat: RDS 알림 규칙 추가 (CPU, Storage, Connections)
  - feat: Prometheus storageSpec 활성화 (local-storage)

- **03-31: 보안 강화** (PR #4, #5)
  - feat: Terraform state S3 버킷 KMS 암호화 전환
  - feat: Terraform backend에 KMS kms_key_id 추가
  - feat: Terraform dispatch job plan/apply 분리
  - feat: K8s Deployment securityContext 추가
  - feat: NetworkPolicy Egress 규칙 추가

- **03-29: 라이프사이클 개선**
  - fix: Lifecycle 수정

- **03-25: 인프라 재구축 — Composition module (stack) 패턴 적용, dev 환경 로컬 전환**
  - `modules/stack/` 신규 — 9개 공통 모듈 캡슐화
  - `environments/dev/` 삭제 — 로컬 docker-compose로 전환
  - K8s dev overlay, ArgoCD app, helm-values 삭제
  - Prod: state surgery로 제로 다운타임 마이그레이션
  - Staging: state empty (rebuild 대기)
  - Bootstrap OIDC: dev IAM 역할 제거

- **03-18: ArgoCD GitOps 통합**
  - ArgoCD Helm 설치 (argocd 네임스페이스, Dex GitHub SSO, nginx Ingress)
  - App-of-Apps 패턴: root-app → 환경별 Application CRD (dev/staging/prod)
  - 환경별 AppProject: dev(auto-sync), staging(수동, 야간 제한), prod(수동, 평일 오전만)
  - NetworkPolicy 4개 (argocd-server, dex, repo-server, redis)
  - RBAC: GitHub 사용자명 직접 매핑 (개인 계정용)
  - Notifications ConfigMap: GitHub commit status 연동 준비
  - Route 53에 `argocd.my-community.shop` DNS 레코드 추가
  - GitHub webhook으로 즉시 동기화 (3분 폴링 → 즉시)
  - SSH 기반 CD 워크플로우 전면 교체 → infra repo 태그 커밋 방식

- **03-15: 인프라 코드베이스 정리**
  - `.terraform.lock.hcl`을 `.gitignore`에서 제외 → 환경별 lock 파일 커밋 (provider 버전 고정)
  - K8s 매니페스트 AWS Account ID 하드코딩 제거: base deployment 이미지를 placeholder로 변경, Kustomize `images` transformer로 환경별 ECR URI 매핑
  - ECR 토큰 갱신 CronJob: `aws sts get-caller-identity`로 Account ID 동적 조회
  - Lambda-era 레거시 모듈 9개를 `modules/_legacy/`로 이동 (활성 12개와 분리)
  - README.md, report.md, CLAUDE.md 문서 동기화

- **03-14: K8s HA 통합 아키텍처 설계 + 코드 구현**
  - `modules/k8s_ec2/` HA 확장: `master_count`(1/3), `worker_count`, `haproxy_enabled` 변수 추가, count 기반 리소스 전환
  - HAProxy L4 로드밸런서: TCP 6443 패스스루, `/healthz` 헬스체크, 전용 SG + userdata 자동 구성
  - Staging/Prod `main.tf` 재작성: Lambda 모듈 → K8s EC2 + RDS 아키텍처
  - Kustomize base/overlay 구조: 17개 base 매니페스트 + dev/staging/prod overlay (ConfigMap/Ingress 패치, images transformer)
  - Helm Grafana values 환경별 분리 (`kube-prometheus-stack-{dev,staging,prod}.yaml`)
  - `enable_s3_uploads` bool 변수 추가: ARN 기반 count 조건 → 새 환경 첫 apply 실패 수정
  - CI/CD `deploy-k8s.yml` staging/prod 환경 옵션 + 동적 health check URL 추가
  - Lambda-era 모듈 9개 deprecation 표기

- **03-14: Lambda 인프라 제거 — K8s 전환 완료 (Dev)**
  - Dev 환경에서 Lambda 기반 인프라 11개 모듈 제거 (67개 리소스 삭제)
  - 제거 대상: `lambda`, `api_gateway`, `cloudfront`, `acm_cloudfront`, `lambda_websocket`, `api_gateway_websocket`, `dynamodb`, `eventbridge`, `efs`, `cloudwatch`, WebSocket 통합 리소스
  - 메인 도메인 DNS(`my-community.shop`, `api`, `ws`) K8s Worker 노드로 통합
  - S3 `uploads_cors_origins` 업데이트: K8s 서브도메인 → 메인 도메인
  - ECR 추가 레포지토리를 `create_k8s_cluster` 조건에서 분리 (항상 생성)

- **03-14: CI/CD 파이프라인 리포지토리별 분리**
  - 기존: BE 리포에서 FE/BE 모두 배포 → 변경: 각 리포가 자체 `deploy-k8s.yml` 소유
  - FE 리포: 독립 K8s 배포 워크플로우 신규 생성 (Docker build → ECR push → SSH kubectl rollout)
  - BE 리포: FE 컴포넌트 제거, api/ws 전용으로 단순화
  - 동적 Security Group 관리: SSH SG 규칙 추가 → 배포 → 규칙 제거 (보안 강화)

- **03-13: K8s 운영 안정성 강화**
  - MySQL 백업 CronJob: `mysqldump` → S3 업로드 (일일 자동 백업)
  - NetworkPolicy 세분화: app↔data namespace 간 트래픽 제어, hostNetwork Ingress 대응 (`ipBlock` VPC CIDR)
  - S3 스토리지 전환: EFS/hostPath → S3 (`STORAGE_BACKEND=s3`, IAM 역할 기반 인증)
  - ECR 토큰 자동 갱신 CronJob 추가

- **03-12: K8s 마이그레이션 구현 (Phase 1-5)**
  - `modules/k8s_ec2/`: K8s 클러스터 Terraform 모듈 (Master 1 + Worker 2, c7i-flex.large)
  - 보안 그룹 4종: k8s_master, k8s_worker, k8s_internal, k8s_ssh (조건부)
  - IAM 역할: ECR Pull + S3 업로드 권한
  - K8s 매니페스트 31개: Deployment, Service, Ingress, HPA, CronJob, PV/PVC, NetworkPolicy, ServiceMonitor
  - Helm 차트 설정: cert-manager, ingress-nginx, MySQL, Redis, kube-prometheus-stack, metrics-server
  - `source_dest_check = false` 설정 (Calico 직접 라우팅 필수)

- **03-11: SES 이메일 발송 모듈 추가**
  - `modules/ses/`: 신규 모듈 — SES 도메인 인증 (Route 53 TXT + DKIM CNAME 자동 생성)
  - `modules/lambda/`: SES IAM 권한 + `EMAIL_BACKEND`/`EMAIL_FROM`/`FRONTEND_URL` 환경변수
  - `bootstrap/oidc.tf`: SES 관리 IAM 권한 + `iam:TagPolicy` 권한 추가
  - 3개 환경 `main.tf`에 SES 모듈 연결

- **03-10: CloudFront Function 라우트 동기화**
  - 프론트엔드 `HTML_PATHS`와 CloudFront Function `routes` 맵 동기화 (10개 → 19개)
  - 누락 라우트 추가: 알림, 내 활동, 이메일 인증, 사용자 프로필, 관리자 페이지, DM 페이지
  - fallback(`uri + '.html'`)으로 커버 불가능한 경로 명시적 매핑 (admin/*, messages/*)

- **03-09: 수평 확장 인프라 — 분산 Rate Limiter + EventBridge 배치 작업**
  - `modules/dynamodb/`: `rate_limit` 테이블 추가 (Fixed Window Counter, TTL 자동 만료)
  - `modules/eventbridge/`: 신규 모듈 — API Destination + Connection (X-Internal-Key 인증)
  - EventBridge 스케줄: 토큰 정리 (1시간), 피드 점수 재계산 (30분)
  - `modules/lambda/`: `INTERNAL_API_KEY` SSM 파라미터 + Rate Limit DynamoDB IAM + 환경변수
  - `bootstrap/oidc.tf`: EventBridge 관리 IAM 권한 추가

- **03-08: WebSocket 실시간 알림 인프라**
  - `modules/dynamodb/`: `ws_connections` 테이블 (user_id GSI 포함)
  - `modules/api_gateway_websocket/`: WebSocket API + Stage ($connect, $disconnect, $default 라우트)
  - `modules/lambda_websocket/`: WebSocket 핸들러 Lambda (ZIP 배포, 순환 참조 방지)
  - 환경 `main.tf`에 standalone Lambda 통합/라우트/권한 리소스 (모듈 순환 참조 해소)
  - Route 53: `ws.my-community.shop` A 레코드 + ACM 인증서
  - REST Lambda IAM: DynamoDB 접근 + API GW ManageConnections 권한 추가

- **03-03: Blue/Green Deployment (Lambda Alias 기반)**
  - Lambda Alias `live` 추가 (`modules/lambda/main.tf`): API Gateway → Alias → Version N 구조
  - Provisioned Concurrency qualifier를 버전 → alias로 변경 (alias 전환 시 PC 자동 적용)
  - API Gateway Lambda permission에 `qualifier` + `create_before_destroy` 추가 (502 방지)
  - 3개 환경 `main.tf`에 alias ARN 연결
  - `bootstrap/oidc.tf`에 Blue/Green IAM 권한 4개 추가

## 2026-02 (Feb)

- **02-28: 전체 코드 리뷰 기반 인프라 개선**
  - Lambda `publish = true` 추가 (Provisioned Concurrency가 `$LATEST` 대신 실제 버전 참조)
  - Bastion 조건부 생성: `create_bastion` 변수 추가, staging/prod에서 비활성화 (비용 절감)
  - RDS `parameter_group_family` 자동 파생 (`engine_version`에서 계산, 별도 변수 제거)
  - CloudTrail 멀티리전 활성화 (`us-east-1` ACM/CloudFront 이벤트 감사 포함)
  - CloudFront 에러 응답: 404/403을 200으로 마스킹 → 원본 상태 코드 유지
  - IAM: `terraform_deployer` 역할 `AdministratorAccess` → `PowerUserAccess` 다운그레이드
  - IAM: `iam:CreatePolicy`를 `${var.project}-*`로 제한 (권한 상승 벡터 차단)
  - 민감 정보 제거: `terraform.tfvars`에서 SSH 공개키/개인 IP → 플레이스홀더 교체
  - CloudTrail `log_retention_days`를 환경별 변수로 전달

- **02-28: 보안 취약점 수정 (Critical)**
  - S3 프론트엔드: 퍼블릭 웹사이트 호스팅 → 비공개 버킷 + CloudFront OAC
  - Lambda 시크릿: 평문 환경변수(`DB_PASSWORD`, `SECRET_KEY`) → SSM Parameter Store SecureString
  - OIDC IAM: AdministratorAccess → 서비스별 스코프 IAM 정책 (최소 권한)

- **02-28: 코드 리뷰 기반 인프라 정리**
  - OIDC IAM: `iam:CreateRole` 등 Resource를 `${var.project}-*` ARN으로 제한 (권한 상승 방지)
  - S3 모듈: 미사용 `cors_allowed_origins` 변수 제거
  - Lambda SSM 정책: KMS 기본 키 사용 설명 주석 추가

- **02-27: GitHub Actions CI/CD 파이프라인 구축**
  - `deploy-infra.yml`: PR → 3환경 matrix plan + PR 코멘트 / `workflow_dispatch` → plan 또는 apply
  - `bootstrap/oidc.tf`: GitHub Actions OIDC provider + 환경별 IAM 역할 (`for_each`)
  - OIDC 인증 (GitHub → AWS STS AssumeRoleWithWebIdentity), fork/upstream 분리

- **02-26: S3 + DynamoDB 원격 상태 백엔드 전환**
  - `modules/tfstate/` 모듈 추가 (S3 버킷 + DynamoDB 테이블)
  - `environments/bootstrap/` 부트스트랩 환경 추가
  - 3개 환경에 `backend "s3"` 블록 추가, 로컬 → S3 마이그레이션

- **02-26: Terraform 인프라 전체 구축**
  - 14개 모듈 설계 및 3개 환경(dev/staging/prod) 배포
  - 서버리스 아키텍처: CloudFront + Lambda + API Gateway + RDS + EFS
  - CloudFront Functions Clean URL, CORS 이중 레이어 설정
  - 환경별 리소스 차등 적용 (Free Tier → HA 구성)
