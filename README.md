# 2-cho-community-infra

커뮤니티 포럼 "아무 말 대잔치"의 AWS 인프라를 Terraform으로 관리하는 저장소입니다.

19개의 재사용 가능한 Terraform 모듈로 구성되며, 3개 환경(dev/staging/prod) + 1개 부트스트랩 환경을 지원합니다. ECS/EKS 대신 서버리스 아키텍처(CloudFront + Lambda + API Gateway)를 채택하여 운영 부담을 최소화하고, 환경별 리소스 규모를 차등 적용하여 비용을 최적화합니다. 콜드 스타트는 Prod의 Provisioned Concurrency(5)로 완화합니다.

## 목표 (Goals)

- 프론트엔드 정적 파일을 S3 + CloudFront로 HTTPS 서빙한다.
- 백엔드 FastAPI 앱을 Lambda 컨테이너로 서버리스 배포한다.
- MySQL(RDS)을 프라이빗 서브넷에 격리하고 Bastion Host로만 직접 접근한다.
- 파일 업로드를 EFS에 영구 저장한다 (Lambda 컨테이너가 다시 생성되어도 파일 보존).
- 환경별(dev/staging/prod) 리소스 규모를 차등 적용하여 비용을 최적화한다.
- CloudWatch 알람/대시보드와 CloudTrail 감사 로그로 모니터링한다.

## 사전 요구사항

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2 (설정 완료)
- AWS 자격 증명 (최초 배포 시 루트 계정 또는 AdministratorAccess 필요)
- 도메인: `my-community.shop` (Route 53 호스팅 영역)
- Docker (Lambda 컨테이너 이미지 빌드용)

## 계획 (Plan)

### 1. 시스템 아키텍처

```mermaid
flowchart TD
    User["사용자 (브라우저)"]

    User -->|"https://my-community.shop"| CF
    User -->|"https://api.my-community.shop"| APIGW

    subgraph Frontend["프론트엔드 경로"]
        CF["CloudFront<br/>CDN + HTTPS + Clean URL"]
        S3["S3 정적 웹사이트<br/>HTML / CSS / JS"]
        CF --> S3
    end

    subgraph Backend["백엔드 경로"]
        APIGW["API Gateway<br/>HTTP API"]
        Lambda["Lambda<br/>FastAPI + Mangum"]
        ECR["ECR<br/>컨테이너 이미지"]
        EFS["EFS<br/>/mnt/uploads"]
        APIGW --> Lambda
        ECR -.->|"이미지 제공"| Lambda
        EFS -.->|"파일 마운트"| Lambda
    end

    subgraph WebSocket["WebSocket 경로"]
        WSGW["WebSocket API Gateway"]
        Lambda_WS["Lambda<br/>WebSocket Handler"]
        WSGW --> Lambda_WS
    end

    User -->|"wss://ws.my-community.shop"| WSGW

    subgraph Data["데이터 계층 (프라이빗 서브넷)"]
        RDS["RDS<br/>MySQL 8.0"]
        DynamoDB["DynamoDB<br/>ws_connections"]
    end

    Lambda --> RDS
    Lambda -->|"푸시 알림"| DynamoDB
    Lambda_WS --> DynamoDB

    subgraph Infra["보조 인프라"]
        VPC["VPC — 2 AZ, 퍼블릭/프라이빗 서브넷, NAT GW"]
        EC2["EC2 Bastion — SSH → RDS 접근"]
        IAM["IAM — 관리자 사용자/그룹/정책"]
        ACM["ACM — SSL 인증서 (ap-northeast-2 + us-east-1)"]
        R53["Route 53 — DNS (my-community.shop)"]
        SES["SES — 이메일 발송 (인증·비밀번호 초기화)"]
        CW["CloudWatch — 알람 + 대시보드"]
        CT["CloudTrail — API 감사 로그"]
    end
```

#### 모듈 의존 관계

```mermaid
flowchart LR
    IAM

    VPC --> RDS
    VPC --> EFS
    VPC --> Lambda
    VPC --> EC2["EC2 (Bastion)"]
    VPC --> CloudWatch

    ECR --> Lambda
    EFS --> Lambda
    RDS --> Lambda
    Lambda --> API_GW["API Gateway"]

    ACM --> API_GW
    Route53["Route 53"] --> API_GW

    CloudWatch --> Lambda
    CloudWatch --> RDS
    CloudWatch --> API_GW

    DynamoDB --> Lambda_WS["Lambda (WebSocket)"]
    Lambda_WS --> WS_APIGW["WebSocket API GW"]
    ACM --> WS_APIGW
    Route53 --> WS_APIGW

    Route53 --> SES
    SES --> Lambda

    S3 --> CloudTrail
    S3 --> CloudFront

    ACM_CF["ACM (us-east-1)"] --> CloudFront
    Route53 --> CloudFront
```

배포 순서: IAM → VPC → S3 → Route 53 → ACM → SES → ECR → RDS → EFS → Lambda → API Gateway → DynamoDB → WebSocket Lambda → WebSocket API Gateway → CloudWatch → EC2 → CloudTrail → ACM (us-east-1) → CloudFront

### 2. 모듈 설계 (19개)

| # | 모듈 | 설명 | 주요 리소스 |
|---|------|------|-------------|
| 0 | `iam` | IAM 사용자/그룹/정책 | IAM User, Group, Policy |
| 1 | `vpc` | 네트워크 + 보안 그룹 | VPC, Subnet, NAT GW, SG |
| 2 | `s3` | 프론트엔드 호스팅 + 로그 저장 | S3 Bucket (website, logs) |
| 3 | `route53` | DNS 호스팅 영역 | Hosted Zone |
| 4 | `acm` | SSL 인증서 (API Gateway용) | ACM Certificate |
| 5 | `ses` | 이메일 발송 (인증·비밀번호 초기화) | SES Domain Identity, DKIM |
| 6 | `ecr` | 컨테이너 이미지 레지스트리 | ECR Repository |
| 7 | `rds` | MySQL 데이터베이스 | RDS Instance, Subnet Group |
| 8 | `efs` | 파일 업로드 스토리지 | EFS File System, Access Point |
| 9 | `lambda` | 백엔드 함수 | Lambda Function, IAM Role |
| 10 | `api_gateway` | API 라우팅 + 커스텀 도메인 | HTTP API, Stage, Domain |
| 11 | `cloudwatch` | 모니터링 | Alarms, Dashboard |
| 12 | `ec2` | Bastion Host | EC2 Instance, EIP, Key Pair |
| 13 | `cloudtrail` | 감사 로그 | CloudTrail |
| 14 | `acm` (us-east-1) | SSL 인증서 (CloudFront용) | ACM Certificate |
| 15 | `cloudfront` | CDN + HTTPS + Clean URL | Distribution, Function |
| 16 | `dynamodb` | WebSocket 연결 저장소 | DynamoDB Table (ws_connections) |
| 17 | `api_gateway_websocket` | WebSocket API 라우팅 | WebSocket API, Stage |
| 18 | `lambda_websocket` | WebSocket 핸들러 | Lambda Function (ZIP), IAM Role |
| 19 | `tfstate` | Terraform 원격 상태 백엔드 | S3 Bucket, DynamoDB Table |

#### 디렉토리 구조

```text
2-cho-community-infra/
├── modules/                    # 재사용 가능한 Terraform 모듈
│   ├── iam/
│   ├── vpc/
│   ├── s3/
│   ├── route53/
│   ├── acm/
│   ├── ses/
│   ├── ecr/
│   ├── rds/
│   ├── efs/
│   ├── lambda/
│   ├── api_gateway/
│   ├── cloudwatch/
│   ├── ec2/
│   ├── cloudtrail/
│   ├── cloudfront/
│   ├── dynamodb/
│   ├── api_gateway_websocket/
│   ├── lambda_websocket/
│   └── tfstate/                # S3 + DynamoDB 원격 상태 백엔드
│
├── environments/               # 환경별 설정
│   ├── bootstrap/              # 상태 백엔드 + OIDC 부트스트랩 (로컬 상태, 1회 실행)
│   ├── dev/
│   │   ├── main.tf             # 모듈 호출 + 프로바이더 설정
│   │   ├── variables.tf        # 변수 선언
│   │   ├── terraform.tfvars    # 변수 값 (비밀 제외)
│   │   ├── outputs.tf          # 출력값 정의
│   │   └── locals.tf           # 공통 태그
│   ├── staging/
│   └── prod/
│
└── README.md
```

### 3. 네트워크 설계

각 환경(dev/staging/prod)에 독립 VPC를 할당하여 CIDR 충돌을 방지합니다. VPC Peering이 필요한 경우 기존 CIDR(`10.0/1/2.0.0/16`)과 겹치지 않도록 설계해야 합니다.

#### VPC CIDR 계획

| 환경 | VPC CIDR | 퍼블릭 서브넷 | 프라이빗 서브넷 |
|------|----------|---------------|-----------------|
| Dev | `10.0.0.0/16` | `10.0.0.0/24`, `10.0.1.0/24` | `10.0.100.0/24`, `10.0.101.0/24` |
| Staging | `10.1.0.0/16` | `10.1.0.0/24`, `10.1.1.0/24` | `10.1.100.0/24`, `10.1.101.0/24` |
| Prod | `10.2.0.0/16` | `10.2.0.0/24`, `10.2.1.0/24` | `10.2.100.0/24`, `10.2.101.0/24` |

- 퍼블릭 서브넷: `cidrsubnet(vpc_cidr, 8, index)` — Bastion, NAT Gateway 배치
- 프라이빗 서브넷: `cidrsubnet(vpc_cidr, 8, index + 100)` — Lambda, RDS, EFS 배치
- 가용 영역: `ap-northeast-2a`, `ap-northeast-2b` (2 AZ)

#### NAT Gateway 전략

Dev/Staging에서는 단일 NAT Gateway($32/월)로 비용을 절감하고, Prod에서만 AZ별 NAT Gateway를 배치하여 고가용성을 확보합니다.

| 환경 | NAT Gateway | 비용 | 장애 내성 |
|------|-------------|------|-----------|
| Dev | 1개 (단일) | ~$32/월 | AZ 단일 장애점 |
| Staging | 1개 (단일) | ~$32/월 | AZ 단일 장애점 |
| Prod | **AZ별 1개** | ~$64/월 | AZ 장애 시에도 가용 |

Prod 환경만 `single_nat_gateway = false`로 설정하여 각 AZ에 독립 NAT Gateway를 배치합니다.

#### 보안 그룹

```mermaid
flowchart TD
    Admin["관리자<br/>(IP 허용목록)"]

    subgraph Public["퍼블릭 서브넷"]
        Bastion["Bastion SG"]
    end

    subgraph Private["프라이빗 서브넷"]
        LambdaSG["Lambda SG"]
        RDSSG["RDS SG"]
        EFSSG["EFS SG"]
    end

    Admin -->|"TCP 22 (SSH)"| Bastion
    Bastion -->|"TCP 3306"| RDSSG
    LambdaSG -->|"TCP 3306"| RDSSG
    LambdaSG -->|"TCP 2049 (NFS)"| EFSSG
```

| 보안 그룹 | 인바운드 | 소스 |
|-----------|----------|------|
| Lambda | 없음 (아웃바운드만) | — |
| RDS | TCP 3306 | Lambda SG, Bastion SG |
| EFS | TCP 2049 | Lambda SG |
| Bastion | TCP 22 | `bastion_allowed_cidrs` (IP 허용목록) |

### 4. 컴퓨트 및 스토리지

#### Lambda (백엔드)

| 설정 | Dev | Staging | Prod |
|------|-----|---------|------|
| 메모리 | 256 MB | 512 MB | 1024 MB |
| 타임아웃 | 30초 | 30초 | 30초 |
| Provisioned Concurrency | 0 | 0 | **5** |
| 로그 보존 | 7일 | 14일 | 30일 |

Lambda 환경변수:
- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_NAME` — RDS 연결
- `DB_PASSWORD_SSM_NAME` — SSM Parameter Store에서 DB 비밀번호 조회 (SecureString)
- `SECRET_KEY_SSM_NAME` — SSM Parameter Store에서 JWT 서명키 조회 (SecureString)
- `ALLOWED_ORIGINS` — CORS 허용 오리진 (JSON 배열)
- `UPLOAD_DIR=/mnt/uploads` — EFS 마운트 경로
- `AWS_LAMBDA_EXEC=true` — 로컬/Lambda 환경 분기
- `HTTPS_ONLY=true` — Secure 쿠키 플래그
- `WS_API_ENDPOINT` — WebSocket API Gateway Management API 엔드포인트
- `WS_CONNECTIONS_TABLE` — DynamoDB 연결 테이블 이름
- `EMAIL_BACKEND` — 이메일 발송 백엔드 (`ses` 또는 `smtp`)
- `EMAIL_FROM` — 발신 이메일 주소 (`noreply@my-community.shop`)
- `FRONTEND_URL` — 프론트엔드 URL (이메일 인증 링크용)

#### RDS (데이터베이스)

| 설정 | Dev | Staging | Prod |
|------|-----|---------|------|
| 인스턴스 | `db.t3.micro` | `db.t3.small` | `db.t3.medium` |
| 초기 스토리지 | 20 GB | 20 GB | 50 GB |
| 최대 스토리지 | 20 GB | 100 GB | 200 GB |
| Multi-AZ | No | No | **Yes** |
| 백업 보존 | 1일 | 3일 | 14일 |
| 삭제 보호 | No | No | **Yes** |

#### S3 (프론트엔드 + 로그)

- **프론트엔드 버킷**: 비공개 버킷 (퍼블릭 액세스 전면 차단), CloudFront OAC로만 접근
- **CloudTrail 로그 버킷**: API 감사 로그 저장

#### EFS (파일 업로드)

Lambda 파일시스템에 직접 마운트 가능한 EFS를 선택했습니다. S3는 SDK 호출이 필요하고 기존 로컬 파일시스템 코드(`utils/storage.py`)의 수정이 크기 때문입니다.

- 마운트 경로: `/mnt/uploads`
- 접근 방식: Access Point (POSIX UID/GID)
- Lambda IAM 조건부 권한: 파일 시스템 ARN을 Resource로, 액세스 포인트를 Condition으로 지정

#### ECR (컨테이너 이미지)

| 환경 | 이미지 보존 수 |
|------|---------------|
| Dev | 3개 |
| Staging | 10개 |
| Prod | 20개 |

### 5. CDN 및 DNS

#### CloudFront

- **오리진**: S3 버킷 (OAC — Origin Access Control로 접근)
- **SSL**: ACM 인증서 (반드시 `us-east-1` 리전에 생성)
- **Clean URL**: CloudFront Functions로 URL 재작성 (CloudFront Functions는 단순 URL 재작성에 적합하며 Lambda@Edge 대비 비용 1/6, 지연시간 <1ms)

```text
요청 경로          →  S3 오브젝트
/                  →  /post_list.html
/main              →  /post_list.html
/login             →  /user_login.html
/signup            →  /user_signup.html
/write             →  /post_write.html
/detail            →  /post_detail.html
/edit              →  /post_edit.html
/password          →  /user_password.html
/edit-profile      →  /user_edit.html
/find-account      →  /user_find_account.html
```

CloudFront Function의 `routes` 맵은 프론트엔드 `constants.js`의 `HTML_PATHS`와 반드시 동기화해야 합니다.

#### Route 53

- 호스팅 영역: `my-community.shop`
- A 레코드 (Alias): `my-community.shop` → CloudFront 배포
- A 레코드 (Alias): `api.my-community.shop` → API Gateway 커스텀 도메인
- A 레코드 (Alias): `ws.my-community.shop` → WebSocket API Gateway 커스텀 도메인

#### ACM 인증서

| 용도 | 리전 | 도메인 | SAN |
|------|------|--------|-----|
| API Gateway | `ap-northeast-2` | `api.my-community.shop` | `my-community.shop` |
| CloudFront | `us-east-1` | `my-community.shop` | — |

#### SES (이메일 발송)

- **도메인 인증**: `my-community.shop` (Route 53 TXT + DKIM CNAME 자동 생성)
- **발신 주소**: `noreply@my-community.shop`
- **용도**: 이메일 인증, 임시 비밀번호 발급
- **Lambda 연동**: `enable_ses = true` 시 SES IAM 권한 + 환경변수 자동 설정

### 6. 보안 설계

#### IAM

- **관리자 사용자**: `terraform.tfvars`의 `admin_username`으로 생성
- **관리자 그룹**: `AdministratorAccess` 정책 연결
- **부트스트랩 순서**: 최초 `terraform apply`는 루트 자격 증명 필수 (IAM 사용자가 자신의 권한 생성 불가)
- **MFA CLI 인증**: `aws sts get-session-token --serial-number <arn> --token-code <code>`

#### 민감 변수 관리

`db_username`, `db_password`, `secret_key`는 `terraform.tfvars`에 포함하지 않습니다.

| 방법 | 명령어 |
|------|--------|
| CLI 플래그 | `terraform apply -var="db_password=xxx"` |
| 별도 파일 | `terraform apply -var-file="secret.tfvars"` |
| 환경 변수 | `export TF_VAR_db_password=xxx` |

`secret.tfvars`는 `.gitignore`에 포함되어 있습니다.

#### CORS 이중 레이어

API Gateway의 `cors_configuration`과 Lambda(FastAPI)의 `CORSMiddleware`가 모두 CORS를 처리합니다. `terraform.tfvars`의 `cors_allowed_origins`와 Lambda 환경변수 `ALLOWED_ORIGINS`가 자동으로 동기화됩니다.

#### Terraform 상태 관리

S3 + DynamoDB 원격 백엔드를 사용합니다. 단일 S3 버킷(`my-community-tfstate`)에 환경별 키(`dev/`, `staging/`, `prod/`)로 분리 저장하고, DynamoDB 테이블(`terraform-locks`)로 동시 실행을 방지합니다. S3 Versioning으로 상태 파일 복구가 가능합니다. 부트스트랩 환경(`environments/bootstrap/`)은 로컬 상태를 영구적으로 사용합니다 (chicken-and-egg 문제 회피).

### 7. 모니터링

#### CloudWatch

- **Lambda 알람**: 에러율, Duration, Throttle
- **RDS 알람**: CPU, 여유 스토리지, 여유 메모리
- **API Gateway 알람**: 5xx 에러율, Latency
- **대시보드**: 주요 지표 통합 뷰

#### CloudTrail

- API 감사 로그 → S3 버킷 저장
- 관리 이벤트 기록 (리소스 생성/삭제/변경 추적)
- **멀티리전**: 모든 AWS 리전의 API 호출 감사 (`us-east-1`의 ACM/CloudFront 이벤트 포함)

#### 로그 보존

| 로그 유형 | Dev | Staging | Prod |
|-----------|-----|---------|------|
| Lambda 실행 로그 | 7일 | 14일 | 30일 |
| API Gateway 액세스 로그 | 7일 | 14일 | 30일 |
| CloudTrail 감사 로그 | 30일 | 60일 | 90일 |

### 8. 배포 전략

#### 부트스트랩 (최초 1회)

S3 버킷, DynamoDB 테이블, GitHub Actions OIDC 프로바이더를 먼저 생성해야 합니다.

```bash
cd environments/bootstrap

terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# 출력값 확인 (backend 설정에 사용)
terraform output tfstate_bucket_id       # my-community-tfstate
terraform output dynamodb_table_name     # terraform-locks
terraform output oidc_provider_arn       # GitHub Actions OIDC ARN
terraform output github_actions_role_arns # 환경별 IAM 역할 ARN
```

> **주의**: bootstrap은 OIDC provider를 관리합니다. 절대 `terraform destroy`하지 마세요.

#### 상태 마이그레이션 (로컬 → S3)

기존에 `terraform apply`를 실행한 환경이 있다면, 로컬 상태를 S3로 마이그레이션합니다.

```bash
cd environments/dev

# backend "s3" 블록이 추가된 상태에서 init 실행
# "Do you want to copy existing state to the new backend?" → yes
terraform init

# 마이그레이션 확인 (변경사항 0건이어야 정상)
terraform plan \
  -var="db_username=DB사용자명" \
  -var="db_password=DB비밀번호" \
  -var="secret_key=JWT시크릿키"

# 확인 후 로컬 상태 파일 삭제
rm -f terraform.tfstate terraform.tfstate.backup
```

staging, prod도 동일하게 반복합니다.

#### Terraform 초기화 및 적용

```bash
cd environments/dev

# 초기화 (프로바이더 다운로드)
terraform init

# 설정 검증
terraform validate

# 변경 사항 확인
terraform plan \
  -var="db_username=DB사용자명" \
  -var="db_password=DB비밀번호" \
  -var="secret_key=JWT시크릿키"

# 적용
terraform apply \
  -var="db_username=DB사용자명" \
  -var="db_password=DB비밀번호" \
  -var="secret_key=JWT시크릿키"
```

#### 출력값 확인

```bash
terraform output                              # 전체 출력
terraform output rds_endpoint                  # RDS 엔드포인트
terraform output ecr_repository_url            # ECR URL
terraform output bastion_public_ip             # Bastion IP
terraform output frontend_url                  # 프론트엔드 URL
terraform output -raw admin_initial_password   # 관리자 초기 비밀번호
```

#### 백엔드 배포 (Blue/Green — Lambda Alias)

배포는 GitHub Actions `deploy-backend.yml`을 통해 자동화되어 있습니다.

```
GitHub Actions 흐름:
  Docker Build → ECR Push → Lambda Version Publish
    → Health Check (새 버전 직접 호출) → Alias "live" 전환
```

수동 배포 시:

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin $(terraform output -raw ecr_repository_url | cut -d/ -f1)

# 이미지 빌드 (--provenance=false 필수)
docker build --provenance=false -t my-community-backend ../2-cho-community-be/

# 태그 및 푸시
ECR_URL=$(terraform output -raw ecr_repository_url)
docker tag my-community-backend:latest $ECR_URL:latest
docker push $ECR_URL:latest

# Lambda 함수 업데이트 + 새 버전 발행
NEW_VERSION=$(aws lambda update-function-code \
  --function-name $(terraform output -raw lambda_function_name) \
  --image-uri $ECR_URL:latest \
  --publish --output json | jq -r '.Version')

aws lambda wait function-updated \
  --function-name $(terraform output -raw lambda_function_name)

# Alias 전환 (health check 통과 후)
aws lambda update-alias \
  --function-name $(terraform output -raw lambda_function_name) \
  --name "live" --function-version "$NEW_VERSION"
```

#### 백엔드 롤백

```bash
# 현재 alias 버전 확인
aws lambda get-alias \
  --function-name $(terraform output -raw lambda_function_name) \
  --name "live" --query 'FunctionVersion' --output text

# 이전 버전으로 롤백 (예: 버전 5로)
aws lambda update-alias \
  --function-name $(terraform output -raw lambda_function_name) \
  --name "live" --function-version "5"
```

또는 GitHub Actions `rollback-backend.yml`에서 환경과 버전을 선택하여 실행합니다.

#### 프론트엔드 배포 (S3 + CloudFront)

```bash
# S3 동기화
aws s3 sync ../2-cho-community-fe/ s3://my-community-dev-frontend \
  --exclude ".git/*" --exclude "node_modules/*" --exclude "tests/*" \
  --exclude "playwright*" --exclude "package*"

# CloudFront 캐시 무효화
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

#### Bastion Host 접속 (RDS 관리)

```bash
# SSH 접속 (Amazon Linux 2023: ec2-user)
ssh -i ~/.ssh/키파일 ec2-user@$(terraform output -raw bastion_public_ip)

# RDS 접속 (bastion에서)
mysql -h <RDS엔드포인트> -u <DB사용자명> -p <DB이름>
```

#### 리소스 제거

```bash
terraform destroy \
  -var="db_username=DB사용자명" \
  -var="db_password=DB비밀번호" \
  -var="secret_key=JWT시크릿키"
```

## 환경별 설정 요약

| 항목 | Dev | Staging | Prod |
|------|-----|---------|------|
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` | `10.2.0.0/16` |
| NAT Gateway | 1개 | 1개 | AZ별 1개 |
| Lambda 메모리 | 256 MB | 512 MB | 1024 MB |
| Provisioned Concurrency | 0 | 0 | 5 |
| RDS 인스턴스 | `db.t3.micro` | `db.t3.small` | `db.t3.medium` |
| RDS Multi-AZ | No | No | Yes |
| RDS 백업 보존 | 1일 | 3일 | 14일 |
| EC2 Bastion | `t3.micro` | 비활성화 | 비활성화 |
| ECR 이미지 보존 | 3개 | 10개 | 20개 |
| 로그 보존 | 7일 | 14일 | 30일 |
| 삭제 보호 (RDS) | No | No | Yes |

## 주의사항

- **민감 변수**: `db_password`, `secret_key`는 절대 `terraform.tfvars`에 넣지 않기
- **CloudFront ACM**: CloudFront용 인증서는 반드시 `us-east-1` 리전에 생성
- **Docker Lambda**: 이미지 빌드 시 `--provenance=false` 필수 (OCI manifest 거부)
- **Lambda 파일시스템**: `/var/task` 읽기 전용, 쓰기는 `/tmp` 또는 EFS(`/mnt/uploads`)
- **EFS 정책**: resource policy 추가 시 implicit allow 사라짐 → Allow 문 필수
- **EC2 AMI**: Amazon Linux 2023은 루트 볼륨 최소 30GB, SSH 사용자는 `ec2-user`
- **CORS 이중 레이어**: API Gateway와 Lambda(FastAPI) 양쪽 모두 CORS 설정 필요
- **CloudFront Function 동기화**: URL 매핑은 프론트엔드 `constants.js`의 `HTML_PATHS`와 일치해야 함
- **Lambda `publish = true`**: Provisioned Concurrency 사용 시 필수. 미설정 시 `$LATEST` 참조로 AWS 거부
- **Bastion 조건부 생성**: `create_bastion = false`로 staging/prod에서 비활성화. Dev만 기본 활성화
- **RDS parameter_group_family**: `modules/rds`에서 `engine_version`으로 자동 파생 — 별도 변수 불필요
- **민감 정보 커밋 금지**: `bastion_ssh_public_key`, `bastion_allowed_cidrs`는 `-var` 또는 `secret.tfvars` 사용
- **환경 파일 동기화**: `main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`는 3개 환경에서 동일 구조 유지
- **IAM 부트스트랩**: 최초 배포 시 루트 자격 증명 필수 (IAM 사용자가 자신의 권한 생성 불가)
- **점진적 배포**: `main.tf` 모듈 주석 처리 시 `outputs.tf`의 해당 output도 주석 처리 필수
- **Lambda 베이스 이미지**: Python 3.12+는 AL2023(`dnf`), 3.11 이하는 AL2(`yum`)
- **부트스트랩 상태**: `environments/bootstrap/`은 영구 로컬 상태 사용. S3 백엔드로 전환 불가 (자기 자신을 저장할 버킷이 아직 없음). OIDC provider도 bootstrap에서 관리하므로 절대 destroy 금지
- **GitHub Actions OIDC**: `bootstrap/oidc.tf`에서 OIDC provider + 환경별 IAM 역할 관리. OIDC subject claim 형식: `repo:ORG/REPO:environment:ENV`. fork/upstream 분리 설정은 `bootstrap/terraform.tfvars`의 `github_fork_owner`/`github_upstream_owner`
- **backend 블록 리터럴**: `backend "s3" {}` 블록에는 변수/locals 사용 불가. Terraform이 변수 평가 전에 백엔드를 초기화하기 때문
- **DynamoDB `LockID`**: hash_key 이름은 대소문자 구분. 반드시 `"LockID"` (S3 백엔드가 사용하는 고정 키 이름)
- **Lambda Alias `live`**: API Gateway가 alias ARN을 참조. `lifecycle { ignore_changes = [function_version] }`로 Terraform이 CD의 alias 변경을 덮어쓰지 않음
- **Blue/Green 배포 IAM**: `bootstrap/oidc.tf`의 LambdaUpdate 문에 `lambda:PublishVersion`, `lambda:GetAlias`, `lambda:UpdateAlias`, `lambda:InvokeFunction` 필수
- **Provisioned Concurrency + Alias**: PC qualifier는 alias name 사용 (`aws_lambda_alias.live.name`). 버전 번호 대신 alias를 지정해야 alias 전환 시 PC가 자동으로 새 버전에 적용
- **WebSocket Lambda는 ZIP 배포**: REST Lambda(Container)와 달리 WebSocket Lambda는 `data "archive_file"` ZIP 패키지 사용. CD에서 `aws lambda update-function-code --zip-file` 사용
- **순환 참조 해소**: `api_gateway_websocket` 모듈은 API+Stage만 생성. Lambda 통합/라우트/권한은 환경 `main.tf`에서 standalone resource로 관리
