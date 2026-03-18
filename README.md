# 2-cho-community-infra

커뮤니티 포럼 "아무 말 대잔치"의 AWS 인프라를 Terraform으로 관리하는 저장소입니다.

12개의 활성 Terraform 모듈 + 9개의 레거시 모듈(`_legacy/`)로 구성되며, 3개 환경(dev/staging/prod) + 1개 부트스트랩 환경을 지원합니다. **kubeadm 기반 K8s 클러스터**로 백엔드/프론트엔드/WebSocket을 컨테이너 운영합니다. Dev는 단일 Master(1M + 2W), Staging/Prod는 HA 구성(3M + 2W + HAProxy)으로 설계되어 있으며, 환경별 리소스 규모를 차등 적용하여 비용을 최적화합니다.

## 목표 (Goals)

- kubeadm K8s 클러스터에서 백엔드(FastAPI), 프론트엔드(nginx), WebSocket을 컨테이너로 운영한다.
- MySQL(RDS)을 프라이빗 서브넷에 격리하고 Bastion Host로만 직접 접근한다.
- 파일 업로드를 S3에 저장한다 (IAM 역할 기반 인증).
- 환경별(dev/staging/prod) 리소스 규모를 차등 적용하여 비용을 최적화한다.
- Prometheus + Grafana로 클러스터 모니터링하고, CloudTrail로 AWS API를 감사한다.

## 사전 요구사항

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2 (설정 완료)
- AWS 자격 증명 (최초 배포 시 루트 계정 또는 AdministratorAccess 필요)
- 도메인: `my-community.shop` (Route 53 호스팅 영역)
- Docker (컨테이너 이미지 빌드용, `--platform linux/amd64` 필수)
- kubectl (K8s 클러스터 관리용)

## 계획 (Plan)

### 1. 시스템 아키텍처

```mermaid
flowchart TD
    User["사용자 (브라우저)"]

    User -->|"https://my-community.shop"| R53
    User -->|"https://api.my-community.shop"| R53
    User -->|"wss://ws.my-community.shop/ws"| R53

    R53["Route 53<br/>DNS → Worker IP"]

    R53 --> Ingress

    subgraph K8s["K8s Cluster (kubeadm · Dev: 1M+2W / Staging·Prod: 3M+2W+HAProxy)"]
        Ingress["Ingress Controller<br/>nginx · hostNetwork · DaemonSet<br/>cert-manager (Let's Encrypt)"]

        subgraph AppNS["app namespace"]
            FE["Frontend Pod<br/>nginx + Vite 빌드 정적 파일"]
            API["API Pod<br/>FastAPI + Uvicorn<br/>HPA 자동 스케일링"]
            WS["WS Pod<br/>WebSocket Server<br/>Redis Pub/Sub"]
            CronJobs["CronJobs<br/>토큰 정리 · 피드 재계산<br/>MySQL 백업 · ECR 토큰 갱신"]
        end

        subgraph DataNS["data namespace"]
            MySQL["MySQL 8.0<br/>StatefulSet · hostPath PV"]
            Redis["Redis<br/>Rate Limiter · WebSocket 세션"]
        end

        subgraph MonNS["monitoring namespace"]
            Prometheus["Prometheus + Grafana<br/>kube-prometheus-stack"]
            MetricsSrv["metrics-server<br/>HPA 메트릭"]
        end

        subgraph ArgoNS["argocd namespace"]
            ArgoCD["ArgoCD<br/>App-of-Apps · GitHub SSO<br/>auto-sync (dev)"]
        end

        Ingress --> FE
        Ingress --> API
        Ingress --> WS
        Ingress -->|"argocd.my-community.shop"| ArgoCD
        API --> MySQL
        API --> Redis
        WS --> Redis
    end

    subgraph AWS["AWS 관리형 서비스"]
        RDS["RDS MySQL 8.0<br/>(프라이빗 서브넷)"]
        S3["S3<br/>업로드 파일 · CloudTrail 로그"]
        ECR["ECR<br/>컨테이너 이미지"]
        ACM["ACM<br/>SSL 인증서 (API Gateway 레거시)"]
        SES["SES<br/>이메일 발송"]
        CT["CloudTrail<br/>감사 로그"]
    end

    subgraph CD["GitOps CD"]
        GHA["GitHub Actions<br/>Build → ECR Push → Tag Commit"]
        InfraRepo["Infra Repo<br/>kustomization.yaml<br/>newTag: sha-XXXX"]
    end

    GHA -->|"docker push"| ECR
    GHA -->|"kustomize edit set image"| InfraRepo
    InfraRepo -->|"webhook → auto-sync"| ArgoCD
    ArgoCD -->|"kubectl apply"| AppNS

    API -->|"파일 업로드<br/>STORAGE_BACKEND=s3"| S3
    API -->|"이메일 발송"| SES
    ECR -.->|"이미지 Pull"| K8s

    style K8s fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style AWS fill:#e3f2fd,stroke:#1565c0
```

#### 모듈 의존 관계

```mermaid
flowchart LR
    IAM

    VPC --> RDS
    VPC --> EC2["EC2 (Bastion)"]
    VPC --> K8s_EC2["K8s EC2"]

    ECR --> K8s_EC2

    Route53["Route 53"] --> ACM
    Route53 --> SES
    Route53 --> K8s_EC2

    S3 --> CloudTrail
    S3 --> K8s_EC2
```

배포 순서: IAM → VPC → S3 → Route 53 → ACM → SES → ECR → RDS → EC2 → CloudTrail → K8s EC2 → DNS 레코드

### 2. 모듈 설계 (활성 12개 + 레거시 9개)

| # | 모듈 | 설명 | 상태 |
|---|------|------|------|
| 0 | `iam` | IAM 사용자/그룹/정책 | 활성 |
| 1 | `vpc` | 네트워크 + 보안 그룹 | 활성 |
| 2 | `s3` | 업로드 파일 + CloudTrail 로그 | 활성 |
| 3 | `route53` | DNS 호스팅 영역 | 활성 |
| 4 | `acm` | SSL 인증서 | 활성 |
| 5 | `ses` | 이메일 발송 (인증·비밀번호) | 활성 |
| 6 | `ecr` | 컨테이너 이미지 레지스트리 | 활성 |
| 7 | `rds` | MySQL 데이터베이스 | 활성 |
| 8 | `ec2` | Bastion Host (SSH → RDS) | 활성 |
| 9 | `cloudtrail` | 감사 로그 | 활성 |
| 10 | `k8s_ec2` | K8s 클러스터 (Dev: 1M+2W / Staging·Prod: 3M+2W+HAProxy) | 활성 |
| 11 | `tfstate` | Terraform 원격 상태 백엔드 | Bootstrap |
| 12 | `efs` | 파일 업로드 (Lambda 마운트) | 레거시 |
| 13 | `lambda` | 백엔드 함수 | 레거시 |
| 14 | `api_gateway` | API 라우팅 | 레거시 |
| 15 | `cloudwatch` | CloudWatch 알람 + 대시보드 | 레거시 |
| 16 | `cloudfront` | CDN + HTTPS + Clean URL | 레거시 |
| 17 | `dynamodb` | WebSocket 연결 + Rate Limiter | 레거시 |
| 18 | `api_gateway_websocket` | WebSocket API 라우팅 | 레거시 |
| 19 | `lambda_websocket` | WebSocket 핸들러 | 레거시 |

> **레거시 모듈**: K8s 마이그레이션 전 서버리스 아키텍처용. `modules/_legacy/`에 보존하되 환경에서 사용하지 않음.

#### 디렉토리 구조

```text
2-cho-community-infra/
├── modules/                    # Terraform 모듈 (활성 12개 + 레거시 9개)
│   ├── iam/
│   ├── vpc/
│   ├── s3/
│   ├── route53/
│   ├── acm/
│   ├── ses/
│   ├── ecr/
│   ├── rds/
│   ├── ec2/
│   ├── cloudtrail/
│   ├── k8s_ec2/               # K8s 클러스터
│   ├── tfstate/
│   └── _legacy/               # Lambda 아키텍처 레거시 (9개)
│       ├── efs, lambda, api_gateway, cloudwatch,
│       └── cloudfront, dynamodb, api_gateway_websocket,
│           lambda_websocket, eventbridge
│
├── k8s/                        # K8s 매니페스트 (Kustomize base/overlay)
│   ├── base/                   # 환경 공통 매니페스트
│   │   ├── kustomization.yaml
│   │   ├── namespaces.yaml     # 4개: ingress-system, app, data, monitoring
│   │   ├── app/                # Deployment, Service, Ingress, CronJob, HPA
│   │   │   ├── api-deployment.yaml, api-service.yaml, api-hpa.yaml
│   │   │   ├── ws-deployment.yaml, ws-service.yaml
│   │   │   ├── fe-deployment.yaml, fe-service.yaml
│   │   │   ├── ingress.yaml, configmap.yaml, networkpolicy.yaml
│   │   │   ├── api-servicemonitor.yaml
│   │   │   └── cronjob-{token-cleanup,feed-recompute,ecr-refresh}.yaml
│   │   ├── cert/               # ClusterIssuer (cert-manager)
│   │   ├── network/            # NetworkPolicy (data namespace)
│   │   └── storage/            # StorageClass
│   ├── overlays/               # 환경별 패치 + 리소스
│   │   ├── dev/
│   │   │   ├── kustomization.yaml
│   │   │   ├── configmap-patch.yaml, ingress-patch.yaml
│   │   │   ├── mysql.yaml, cronjob-mysql-backup.yaml
│   │   │   └── storage/       # PV/PVC (환경별 경로·용량)
│   │   ├── staging/
│   │   │   ├── kustomization.yaml
│   │   │   ├── configmap-patch.yaml, ingress-patch.yaml
│   │   │   └── storage/
│   │   └── prod/
│   │       ├── kustomization.yaml
│   │       ├── configmap-patch.yaml, ingress-patch.yaml
│   │       └── storage/
│   └── helm-values/            # Helm 차트 설정 (환경별)
│       ├── cert-manager.yaml, ingress-nginx.yaml
│       ├── mysql.yaml, redis.yaml, metrics-server.yaml
│       └── kube-prometheus-stack-{dev,staging,prod}.yaml
│
├── environments/               # 환경별 설정
│   ├── bootstrap/              # 상태 백엔드 + OIDC 부트스트랩 (로컬 상태)
│   ├── dev/
│   ├── staging/
│   └── prod/
│
├── docs/plans/                 # K8s 마이그레이션 설계·구현 문서
└── .github/workflows/          # Terraform CI/CD
```

### 3. 네트워크 설계

각 환경에 독립 VPC를 할당하여 CIDR 충돌을 방지합니다.

#### VPC CIDR 계획

| 환경 | VPC CIDR | 퍼블릭 서브넷 | 프라이빗 서브넷 |
|------|----------|---------------|-----------------|
| Dev | `10.0.0.0/16` | `10.0.0.0/24`, `10.0.1.0/24` | `10.0.100.0/24`, `10.0.101.0/24` |
| Staging | `10.1.0.0/16` | `10.1.0.0/24`, `10.1.1.0/24` | `10.1.100.0/24`, `10.1.101.0/24` |
| Prod | `10.2.0.0/16` | `10.2.0.0/24`, `10.2.1.0/24` | `10.2.100.0/24`, `10.2.101.0/24` |

- 퍼블릭 서브넷: K8s 노드, Bastion, NAT Gateway 배치
- 프라이빗 서브넷: RDS 배치
- 가용 영역: `ap-northeast-2a`, `ap-northeast-2b` (2 AZ)

#### NAT Gateway 전략

K8s 노드는 퍼블릭 서브넷에 배치되어 NAT Gateway를 경유하지 않습니다. NAT Gateway는 프라이빗 서브넷(RDS 등)의 아웃바운드 트래픽용입니다.

| 환경 | NAT Gateway | 비용 | 장애 내성 |
|------|-------------|------|-----------|
| Dev | 1개 (단일) | ~$32/월 | AZ 단일 장애점 |
| Staging | 1개 (단일) | ~$32/월 | AZ 단일 장애점 |
| Prod | **AZ별 1개** | ~$64/월 | AZ 장애 시에도 가용 |

#### 보안 그룹

```mermaid
flowchart TD
    Admin["관리자<br/>(IP 허용목록)"]
    User["사용자<br/>(인터넷)"]

    subgraph Public["퍼블릭 서브넷"]
        K8sMaster["K8s Master SG<br/>API 6443 · etcd 2379-2380<br/>kubelet 10250-10252"]
        K8sWorker["K8s Worker SG<br/>HTTP 80 · HTTPS 443<br/>kubelet 10250"]
        K8sInternal["K8s Internal SG<br/>노드 간 전 포트 (Calico)"]
        Bastion["Bastion SG"]
    end

    subgraph Private["프라이빗 서브넷"]
        RDSSG["RDS SG"]
    end

    User -->|"TCP 80/443"| K8sWorker
    Admin -->|"TCP 22 (SSH)"| K8sMaster
    Admin -->|"TCP 22 (SSH)"| K8sWorker
    Admin -->|"TCP 22 (SSH)"| Bastion
    K8sMaster <-->|"전 포트"| K8sInternal
    K8sWorker <-->|"전 포트"| K8sInternal
    K8sWorker -->|"TCP 3306"| RDSSG
    Bastion -->|"TCP 3306"| RDSSG
```

| 보안 그룹 | 인바운드 | 소스 |
|-----------|----------|------|
| K8s Master | TCP 6443, 2379-2380, 10250-10252 | K8s Internal SG |
| K8s Worker | TCP 80, 443, 10250 | 0.0.0.0/0 (HTTP/S), K8s Internal SG |
| K8s Internal | 전 포트 | 자기 참조 (노드 간 Calico Pod 네트워크) |
| K8s SSH | TCP 22 | `k8s_allowed_ssh_cidrs` (조건부 생성) |
| HAProxy | TCP 6443 | K8s 노드 (API 서버 로드밸런싱, Staging/Prod) |
| RDS | TCP 3306 | K8s Worker SG, Bastion SG |
| Bastion | TCP 22 | `bastion_allowed_cidrs` |

### 4. 컴퓨트 및 스토리지

#### K8s 클러스터

| 항목 | Dev | Staging | Prod |
|------|-----|---------|------|
| Master | c7i-flex.large × **1** | c7i-flex.large × **3** | c7i-flex.large × **3** |
| Worker | c7i-flex.large × 2 | c7i-flex.large × 2 | c7i-flex.large × 2 |
| HAProxy | 없음 | c7i-flex.large × **1** | c7i-flex.large × **1** |
| API LB | Master 직접 접근 | HAProxy → Master 3대 L4 LB | HAProxy → Master 3대 L4 LB |
| 노드 합계 | **3대** | **6대** | **6대** |
| OS | Amazon Linux 2023 | Amazon Linux 2023 | Amazon Linux 2023 |
| CNI | Calico (직접 라우팅) | Calico | Calico |
| Ingress | nginx (hostNetwork DaemonSet) | nginx | nginx |
| 인증서 | cert-manager + Let's Encrypt | cert-manager | cert-manager |
| 모니터링 | Prometheus + Grafana | Prometheus + Grafana | Prometheus + Grafana |

K8s 워크로드:

| 리소스 | 이름 | 설명 |
|--------|------|------|
| Deployment | `community-api` | FastAPI 백엔드 (HPA 자동 스케일링) |
| Deployment | `community-ws` | WebSocket 서버 (Redis Pub/Sub) |
| Deployment | `community-fe` | nginx + Vite 빌드 정적 파일 |
| CronJob | `token-cleanup` | 만료 Refresh Token 정리 |
| CronJob | `feed-recompute` | 추천 피드 점수 재계산 |
| CronJob | `mysql-backup` | MySQL 데이터 백업 → S3 |
| CronJob | `ecr-refresh` | ECR Pull 토큰 자동 갱신 |
| HPA | `api-hpa` | API Pod 자동 스케일링 |
| Ingress | `community-ingress` | HTTP/HTTPS 라우팅 + TLS 종단 |

#### RDS (데이터베이스)

| 설정 | Dev | Staging | Prod |
|------|-----|---------|------|
| 인스턴스 | `db.t3.micro` | `db.t3.micro` | `db.t3.medium` |
| 초기 스토리지 | 20 GB | 20 GB | 50 GB |
| 최대 스토리지 | 20 GB | 100 GB | 200 GB |
| Multi-AZ | No | No | **Yes** |
| 백업 보존 | 1일 | 1일 | 14일 |
| 삭제 보호 | No | No | **Yes** |

#### 파일 업로드 스토리지

모든 환경에서 S3를 사용합니다 (`STORAGE_BACKEND=s3`). K8s 노드의 IAM 역할에 S3 업로드 권한이 자동 부여됩니다.

#### ECR (컨테이너 이미지)

| 환경 | 이미지 보존 수 | 레포지토리 |
|------|---------------|-----------|
| Dev | 3개 | `backend-k8s`, `frontend-k8s` |
| Staging | 10개 | `backend-k8s`, `frontend-k8s` |
| Prod | 20개 | `backend-k8s`, `frontend-k8s` |

### 5. DNS 및 인증서

#### Route 53

모든 도메인은 K8s Worker 노드의 퍼블릭 IP를 가리키는 A 레코드입니다.

| 레코드 | 설명 |
|--------|------|
| `my-community.shop` | 프론트엔드 (nginx Pod) |
| `api.my-community.shop` | 백엔드 API (FastAPI Pod) |
| `ws.my-community.shop` | WebSocket (WS Pod) |
| `k8s.my-community.shop` | K8s 서브도메인 (레거시 호환) |
| `grafana.k8s.my-community.shop` | Grafana 대시보드 |

#### 인증서

K8s 환경에서는 cert-manager가 Let's Encrypt에서 TLS 인증서를 자동 발급·갱신합니다. Terraform의 ACM 모듈은 레거시 호환용으로 유지됩니다.

#### SES (이메일 발송)

- **도메인 인증**: `my-community.shop` (Route 53 TXT + DKIM CNAME 자동 생성)
- **발신 주소**: `noreply@my-community.shop`
- **용도**: 이메일 인증, 임시 비밀번호 발급

### 6. 보안 설계

#### IAM

- **관리자 사용자**: `terraform.tfvars`의 `admin_username`으로 생성
- **관리자 그룹**: `AdministratorAccess` 정책 연결
- **K8s 노드 역할**: ECR Pull + S3 업로드 권한
- **부트스트랩 순서**: 최초 `terraform apply`는 루트 자격 증명 필수

#### 민감 변수 관리

`db_username`, `db_password`는 `terraform.tfvars`에 포함하지 않습니다.

| 방법 | 명령어 |
|------|--------|
| CLI 플래그 | `terraform apply -var="db_password=xxx"` |
| 별도 파일 | `terraform apply -var-file="secret.tfvars"` |
| 환경 변수 | `export TF_VAR_db_password=xxx` |

`secret.tfvars`는 `.gitignore`에 포함되어 있으며, `bastion_allowed_cidrs`, `k8s_allowed_ssh_cidrs`, `db_password` 등을 관리합니다.

#### K8s NetworkPolicy

- **app namespace**: data namespace(MySQL, Redis)로만 egress 허용
- **data namespace**: app namespace에서만 ingress 허용, `ipBlock`으로 VPC CIDR(`10.0.0.0/16`) 허용 (hostNetwork Ingress 대응)

#### Terraform 상태 관리

S3 + DynamoDB 원격 백엔드를 사용합니다. 단일 S3 버킷(`my-community-tfstate`)에 환경별 키(`dev/`, `staging/`, `prod/`)로 분리 저장합니다. 부트스트랩 환경은 로컬 상태를 영구 사용합니다 (OIDC provider 포함 — 절대 destroy 금지).

### 7. 모니터링

#### Prometheus + Grafana (K8s)

- **설치**: kube-prometheus-stack Helm 차트
- **metrics-server**: HPA 자동 스케일링 메트릭 (`--kubelet-insecure-tls` 필수)
- **접근**: `grafana.k8s.my-community.shop`
- **ServiceMonitor**: FastAPI 앱의 Prometheus 메트릭 자동 수집

#### CloudTrail (AWS)

- API 감사 로그 → S3 버킷 저장
- 멀티리전: 모든 AWS 리전의 API 호출 감사

### 8. 배포 전략

#### 부트스트랩 (최초 1회)

```bash
cd environments/bootstrap
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

> **주의**: bootstrap은 OIDC provider를 관리합니다. 절대 `terraform destroy`하지 마세요.

#### Terraform 초기화 및 적용

```bash
cd environments/dev
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars -var-file=secret.tfvars
terraform apply -var-file=terraform.tfvars -var-file=secret.tfvars
```

#### K8s 클러스터 초기화 (최초 1회)

Terraform이 EC2를 생성하면 User Data 스크립트가 kubeadm, kubelet, Calico CNI를 자동 설치합니다. 이후 Master 노드에서 `kubeadm init`으로 클러스터를 초기화하고, Worker 노드를 조인합니다.

```bash
# Helm 차트 설치 (Master 노드에서)
helm install cert-manager jetstack/cert-manager -f k8s/helm-values/cert-manager.yaml -n cert-manager
helm install ingress-nginx ingress-nginx/ingress-nginx -f k8s/helm-values/ingress-nginx.yaml -n ingress-system
helm install mysql bitnami/mysql -f k8s/helm-values/mysql.yaml -n data
helm install redis bitnami/redis -f k8s/helm-values/redis.yaml -n data
helm install prometheus prometheus-community/kube-prometheus-stack -f k8s/helm-values/kube-prometheus-stack.yaml -n monitoring

# K8s 매니페스트 적용 (Kustomize overlay)
kubectl apply -k k8s/overlays/dev/       # Dev 환경
kubectl apply -k k8s/overlays/staging/   # Staging 환경
kubectl apply -k k8s/overlays/prod/      # Prod 환경
```

#### K8s 배포 (롤링 업데이트)

```bash
# 방법 1: GitHub Actions deploy-k8s.yml (권장)
# BE 리포: api/ws 컴포넌트 선택
# FE 리포: 프론트엔드 전용

# 방법 2: 수동 배포
# 이미지 빌드 (x86_64 필수)
docker build --platform linux/amd64 -t backend-k8s -f Dockerfile.k8s .
docker tag backend-k8s:latest <ECR_URL>:latest
docker push <ECR_URL>:latest

# 롤링 업데이트
kubectl -n app rollout restart deployment/community-api
```

> **주의**: 로컬 Mac(ARM64)에서 빌드한 이미지는 K8s EC2(x86_64)에서 `exec format error` 발생.

#### CI/CD 워크플로우 (리포지토리별)

| 리포지토리 | 워크플로우 | 설명 |
|-----------|-----------|------|
| `2-cho-community-be` | `python-app.yml` | CI: pytest + mypy + ruff |
| `2-cho-community-be` | `deploy-k8s.yml` | K8s CD: api/ws 컴포넌트 |
| `2-cho-community-fe` | `deploy-k8s.yml` | K8s CD: 프론트엔드 |
| `2-cho-community-infra` | `deploy-infra.yml` | Terraform plan/apply |

> 레거시 워크플로우: `deploy-backend.yml` (Lambda), `rollback-backend.yml` (Lambda), `deploy-frontend.yml` (S3 + CloudFront)

모든 CD 워크플로우는 GitHub Actions OIDC로 AWS에 인증합니다 (장기 자격 증명 없음).

#### Bastion Host 접속 (RDS 관리)

```bash
# SSH 터널 생성
ssh -i ~/.ssh/키파일 -L 3307:<RDS엔드포인트>:3306 ec2-user@<Bastion-IP> -N

# 별도 터미널에서 로컬처럼 RDS 접속
mysql -h 127.0.0.1 -P 3307 -u <DB사용자명> -p <DB이름>
```

## 환경별 설정 요약

| 항목 | Dev | Staging | Prod |
|------|-----|---------|------|
| K8s 토폴로지 | 1M + 2W (단일 Master) | **3M + 2W + HAProxy** (HA) | **3M + 2W + HAProxy** (HA) |
| EC2 합계 | 3대 | 6대 | 6대 |
| 인스턴스 | c7i-flex.large | c7i-flex.large | c7i-flex.large |
| 파일 스토리지 | S3 | S3 | S3 |
| WebSocket | WS Pod + Redis | WS Pod + Redis | WS Pod + Redis |
| Rate Limiter | Redis | Redis | Redis |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` | `10.2.0.0/16` |
| NAT Gateway | 1개 | 1개 | AZ별 1개 |
| RDS | `db.t3.micro` | `db.t3.micro` | `db.t3.medium` |
| RDS Multi-AZ | No | No | Yes |
| RDS 백업 보존 | 1일 | 1일 | 14일 |
| EC2 Bastion | `t3.micro` | 비활성화 | 비활성화 |
| ECR 이미지 보존 | 3개 | 10개 | 20개 |
| 모니터링 | Prometheus + Grafana | Prometheus + Grafana | Prometheus + Grafana |
| Kustomize overlay | `overlays/dev/` | `overlays/staging/` | `overlays/prod/` |
| 삭제 보호 (RDS) | No | No | Yes |

> **배포 상태**: Dev 환경만 배포 완료. Staging/Prod HA 아키텍처는 Terraform + Kustomize 코드 완료 상태이나, AWS Free Tier EIP 한도(5개) 초과로 배포 보류 중. 계정 업그레이드 또는 Service Quotas 상향 후 배포 가능.

## 주의사항

- **민감 변수**: `db_password`, SSH CIDR 등은 절대 `terraform.tfvars`에 넣지 않기 — `secret.tfvars` 사용
- **Cross-platform Docker**: Mac(ARM64)에서 K8s용 이미지 빌드 시 `--platform linux/amd64` 필수
- **Terraform `count` 변경 주의**: 모듈의 `count` 제거 시 리소스 주소 변경 → 전체 destroy+recreate 위험
- **Terraform 모듈 제거 시 DNS 연쇄 삭제**: DNS 레코드를 관리하는 모듈 제거 시 해당 DNS도 삭제됨
- **GitHub Actions `workflow_dispatch`**: 워크플로우 파일이 default branch에 존재해야 트리거 가능
- **EC2 AMI**: Amazon Linux 2023은 루트 볼륨 최소 30GB, SSH 사용자는 `ec2-user`
- **K8s metrics-server**: kubeadm 환경에서 `--kubelet-insecure-tls` 플래그 필수
- **hostNetwork Ingress + NetworkPolicy**: `hostNetwork: true` Ingress는 노드 IP에서 트래픽 발생 → `ipBlock`으로 VPC CIDR 허용 필요
- **K8s SSH SG**: `k8s_allowed_ssh_cidrs`와 `bastion_allowed_cidrs`는 별도 Security Group
- **환경 파일 동기화**: `main.tf`는 맹목적 복사 금지 — `backend.key`, 활성 모듈이 환경마다 다름
- **부트스트랩**: `environments/bootstrap/`은 영구 로컬 상태. OIDC provider 포함 — 절대 destroy 금지
