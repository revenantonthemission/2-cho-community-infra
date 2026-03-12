###############################################################################
# Dev Environment - Main Configuration
# 모듈을 하나씩 추가하며 인프라를 점진적으로 구축
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
    key            = "dev/terraform.tfstate"
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

# CloudFront ACM 인증서는 반드시 us-east-1에 생성해야 함
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# Module 0: IAM (루트 계정 대신 사용할 사용자/그룹/정책)
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
# Module 2: S3
# =============================================================================
module "s3" {
  source = "../../modules/s3"

  project     = var.project
  environment = var.environment

  cloudtrail_log_retention_days = var.cloudtrail_log_retention_days

  # 업로드 S3 버킷 (K8s 환경에서 사용)
  create_uploads_bucket = true
  uploads_cors_origins  = ["https://k8s.my-community.shop"]

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

  domain_name               = var.api_domain_name
  subject_alternative_names = [var.domain_name, "ws.${var.domain_name}"]
  zone_id                   = module.route53.zone_id

  tags = local.common_tags
}

# =============================================================================
# Module 3.5: SES (이메일 발송)
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

  additional_repositories = var.create_k8s_cluster ? [
    "${var.project}-${var.environment}-backend-k8s",
    "${var.project}-${var.environment}-frontend-k8s",
  ] : []

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
# Module 6: EFS
# =============================================================================
module "efs" {
  source = "../../modules/efs"

  project     = var.project
  environment = var.environment

  private_subnet_ids    = module.vpc.private_subnet_ids
  efs_security_group_id = module.vpc.efs_security_group_id

  tags = local.common_tags
}

# =============================================================================
# Module 7: Lambda
# =============================================================================
module "lambda" {
  source = "../../modules/lambda"

  project     = var.project
  environment = var.environment

  private_subnet_ids       = module.vpc.private_subnet_ids
  lambda_security_group_id = module.vpc.lambda_security_group_id

  ecr_image_uri        = "${module.ecr.repository_url}:${var.lambda_image_tag}"
  efs_access_point_arn = module.efs.access_point_arn
  efs_file_system_arn  = module.efs.file_system_arn

  db_host          = module.rds.address
  db_port          = module.rds.port
  db_username      = var.db_username
  db_password      = var.db_password
  db_name          = var.db_name
  secret_key       = var.secret_key
  internal_api_key = var.internal_api_key

  # Rate Limiter DynamoDB 설정
  rate_limit_dynamodb_table_arn  = module.dynamodb.rate_limit_table_arn
  rate_limit_dynamodb_table_name = module.dynamodb.rate_limit_table_name

  cors_allowed_origins = var.cors_allowed_origins

  memory_size             = var.lambda_memory_size
  timeout                 = var.lambda_timeout
  provisioned_concurrency = var.lambda_provisioned_concurrency
  log_retention_days      = var.lambda_log_retention_days

  # 이메일 발송 (SES)
  enable_ses              = true
  ses_domain_identity_arn = module.ses.domain_identity_arn
  email_from              = "noreply@${var.domain_name}"
  frontend_url            = "https://${var.domain_name}"

  # WebSocket 푸시 설정
  enable_websocket_push  = true
  aws_region             = var.aws_region
  ws_dynamodb_table_arn  = module.dynamodb.table_arn
  ws_dynamodb_table_name = module.dynamodb.table_name
  ws_api_gateway_id      = module.api_gateway_websocket.api_id
  ws_api_gw_endpoint     = module.api_gateway_websocket.management_endpoint

  tags = local.common_tags
}

# =============================================================================
# Module 8: API Gateway (로그 그룹은 이 모듈 내부에서 생성)
# =============================================================================
module "api_gateway" {
  source = "../../modules/api_gateway"

  project     = var.project
  environment = var.environment

  lambda_invoke_arn    = module.lambda.alias_invoke_arn
  lambda_function_name = module.lambda.function_name
  lambda_alias_name    = module.lambda.alias_name

  cors_allowed_origins = var.cors_allowed_origins
  api_domain_name      = var.api_domain_name
  certificate_arn      = module.acm.certificate_arn
  zone_id              = module.route53.zone_id
  log_retention_days   = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# Module 9: CloudWatch (알람 + 대시보드)
# =============================================================================
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  lambda_function_name = module.lambda.function_name
  rds_instance_id      = module.rds.instance_id
  api_gateway_id       = module.api_gateway.api_id

  log_retention_days = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# Module 10: EC2 + EIP (Bastion Host)
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
# Module 12: ACM (us-east-1 — CloudFront 전용)
# =============================================================================
module "acm_cloudfront" {
  source = "../../modules/acm"

  providers = {
    aws = aws.us_east_1
  }

  project     = var.project
  environment = var.environment

  domain_name               = var.domain_name
  subject_alternative_names = []
  zone_id                   = module.route53.zone_id

  tags = local.common_tags
}

# =============================================================================
# Module 13: CloudFront (프론트엔드 CDN + HTTPS + Clean URL)
# =============================================================================
module "cloudfront" {
  source = "../../modules/cloudfront"

  project     = var.project
  environment = var.environment

  domain_name                    = var.domain_name
  s3_bucket_id                   = module.s3.frontend_bucket_id
  s3_bucket_arn                  = module.s3.frontend_bucket_arn
  s3_bucket_regional_domain_name = module.s3.frontend_bucket_regional_domain_name
  acm_certificate_arn            = module.acm_cloudfront.certificate_arn
  zone_id                        = module.route53.zone_id
  api_domain_name                = var.api_domain_name

  tags = local.common_tags
}

# =============================================================================
# Module 14: DynamoDB (WebSocket 연결 매핑)
# =============================================================================
module "dynamodb" {
  source = "../../modules/dynamodb"

  project     = var.project
  environment = var.environment

  tags = local.common_tags
}

# =============================================================================
# Module 15: WebSocket API Gateway (Lambda 통합 제외 — 순환 참조 방지)
# =============================================================================
module "api_gateway_websocket" {
  source = "../../modules/api_gateway_websocket"

  project     = var.project
  environment = var.environment

  ws_domain_name  = "ws.${var.domain_name}"
  certificate_arn = module.acm.certificate_arn
  zone_id         = module.route53.zone_id

  tags = local.common_tags
}

# =============================================================================
# Module 16: WebSocket Lambda
# =============================================================================
module "lambda_websocket" {
  source = "../../modules/lambda_websocket"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  dynamodb_table_arn  = module.dynamodb.table_arn
  dynamodb_table_name = module.dynamodb.table_name
  secret_key_ssm_arn  = module.lambda.secret_key_ssm_arn
  secret_key_ssm_name = module.lambda.secret_key_ssm_name
  ws_api_endpoint     = module.api_gateway_websocket.management_endpoint
  ws_api_gateway_id   = module.api_gateway_websocket.api_id

  log_retention_days = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# WebSocket API Gateway ↔ Lambda 통합 (순환 참조 방지를 위해 환경 레벨에서 생성)
# =============================================================================
resource "aws_apigatewayv2_integration" "ws_lambda" {
  api_id             = module.api_gateway_websocket.api_id
  integration_type   = "AWS_PROXY"
  integration_uri    = module.lambda_websocket.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "ws_connect" {
  api_id    = module.api_gateway_websocket.api_id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_lambda.id}"
}

resource "aws_apigatewayv2_route" "ws_disconnect" {
  api_id    = module.api_gateway_websocket.api_id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_lambda.id}"
}

resource "aws_apigatewayv2_route" "ws_default" {
  api_id    = module.api_gateway_websocket.api_id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.ws_lambda.id}"
}

resource "aws_lambda_permission" "ws_api_gateway" {
  statement_id  = "AllowWebSocketAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_websocket.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.api_gateway_websocket.execution_arn}/*/*"
}

# =============================================================================
# Module 17: EventBridge (배치 작업 스케줄)
# =============================================================================
# internal_api_key가 비어 있으면 EventBridge 모듈 비활성화 (CI plan 호환)
module "eventbridge" {
  source = "../../modules/eventbridge"
  count  = length(var.internal_api_key) > 0 ? 1 : 0

  project     = var.project
  environment = var.environment

  api_endpoint     = module.api_gateway.custom_domain_url
  internal_api_key = var.internal_api_key

  tags = local.common_tags
}

# ─── K8s Cluster (kubeadm on EC2) ───────────────
module "k8s_ec2" {
  source = "../../modules/k8s_ec2"
  count  = var.create_k8s_cluster ? 1 : 0

  project     = var.project
  environment = var.environment

  vpc_id            = module.vpc.vpc_id
  # c7i-flex.large는 ap-northeast-2a 미지원 → 2b 서브넷만 전달
  public_subnet_ids = [module.vpc.public_subnet_ids[1]]

  ssh_key_name      = var.k8s_ssh_key_name
  allowed_ssh_cidrs = var.k8s_allowed_ssh_cidrs

  s3_uploads_bucket_arn = module.s3.uploads_bucket_arn

  tags = local.common_tags
}

# K8s DNS Records (Worker 노드 IP → 서브도메인)
resource "aws_route53_record" "k8s" {
  for_each = var.create_k8s_cluster ? toset([
    "api.k8s",
    "k8s",
    "ws.k8s",
    "grafana.k8s",
  ]) : toset([])

  zone_id = module.route53.zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = module.k8s_ec2[0].worker_public_ips
}
