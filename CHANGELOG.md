# Changelog

## 2026-03 (Mar)

- **03-11: SES 이메일 발송 모듈 추가**
  - `modules/ses/`: 신규 모듈 — SES 도메인 인증 (Route 53 TXT + DKIM CNAME 자동 생성)
  - `modules/lambda/`: SES IAM 권한 (`ses:SendEmail`, `ses:SendRawEmail`) + `EMAIL_BACKEND`/`EMAIL_FROM`/`FRONTEND_URL` 환경변수
  - `bootstrap/oidc.tf`: SES 관리 IAM 권한 + `iam:TagPolicy` 권한 추가
  - 3개 환경(dev/staging/prod) `main.tf`에 SES 모듈 연결

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
  - 3개 환경(dev/staging/prod) `main.tf`에 alias ARN 연결
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
