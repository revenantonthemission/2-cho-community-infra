###############################################################################
# Lambda Module
# FastAPI 백엔드 (Mangum 핸들러, ECR 컨테이너 이미지)
###############################################################################

# -----------------------------------------------------------------------------
# IAM Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "${var.project}-${var.environment}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# VPC 접근 (ENI 생성 권한)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# CloudWatch Logs 기본 권한
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# EFS 접근 권한
resource "aws_iam_policy" "lambda_efs" {
  name = "${var.project}-${var.environment}-lambda-efs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = var.efs_file_system_arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = var.efs_access_point_arn
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_efs" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_efs.arn
}

# SSM Parameter Store 접근 권한 (시크릿 조회)
# ssm:GetParameter + WithDecryption=True는 기본 aws/ssm 키 사용 시
# 별도 kms:Decrypt 권한 불필요. CMK 전환 시 kms:Decrypt 추가 필요
resource "aws_iam_policy" "lambda_ssm" {
  name = "${var.project}-${var.environment}-lambda-ssm"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.db_password.arn,
          aws_ssm_parameter.secret_key.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ssm" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_ssm.arn
}

# -----------------------------------------------------------------------------
# SSM Parameter Store: 시크릿 암호화 저장
# Lambda 환경변수에 평문 대신 SSM 파라미터 이름만 전달
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project}/${var.environment}/db-password"
  type  = "SecureString"
  value = var.db_password

  tags = var.tags
}

resource "aws_ssm_parameter" "secret_key" {
  name  = "/${var.project}/${var.environment}/secret-key"
  type  = "SecureString"
  value = var.secret_key

  tags = var.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group (Lambda 자동 생성 대신 Terraform으로 관리)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project}-${var.environment}-backend"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda Function
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "backend" {
  function_name = "${var.project}-${var.environment}-backend"
  role          = aws_iam_role.lambda.arn

  package_type = "Image"
  image_uri    = var.ecr_image_uri

  # Provisioned Concurrency가 $LATEST 대신 실제 버전을 참조하도록 게시
  publish = true

  memory_size = var.memory_size
  timeout     = var.timeout

  # VPC 설정 (RDS, EFS 접근)
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  # EFS 마운트
  file_system_config {
    arn              = var.efs_access_point_arn
    local_mount_path = "/mnt/uploads"
  }

  environment {
    variables = {
      # DB 연결 (core/config.py의 Settings와 일치)
      DB_HOST = var.db_host
      DB_PORT = tostring(var.db_port)
      DB_USER = var.db_username
      DB_NAME = var.db_name

      # 시크릿: SSM Parameter Store에서 콜드 스타트 시 조회
      # (평문 대신 파라미터 이름만 저장 → GetFunctionConfiguration으로 노출 방지)
      DB_PASSWORD_SSM_NAME = aws_ssm_parameter.db_password.name
      SECRET_KEY_SSM_NAME  = aws_ssm_parameter.secret_key.name

      # 애플리케이션 설정
      ALLOWED_ORIGINS = jsonencode(var.cors_allowed_origins)
      HTTPS_ONLY      = "true"
      DEBUG           = var.environment == "prod" ? "false" : "true"
      UPLOAD_DIR      = "/mnt/uploads"

      # Lambda 환경 표시
      AWS_LAMBDA_EXEC = "true"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_efs,
    aws_iam_role_policy_attachment.lambda_ssm,
    aws_cloudwatch_log_group.lambda,
  ]

  # CD 파이프라인이 image_uri를 SHA 태그로 관리 — terraform apply가 latest로 되돌리지 않도록 방지
  lifecycle {
    ignore_changes = [image_uri]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-backend"
  })
}

# -----------------------------------------------------------------------------
# Lambda Alias (Blue/Green 배포 — API Gateway가 이 alias를 바라봄)
# CD 파이프라인이 update-alias로 버전을 전환하므로 Terraform은 최초 생성만 담당
# -----------------------------------------------------------------------------
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.backend.function_name
  function_version = aws_lambda_function.backend.version

  # CD 파이프라인이 alias 버전을 관리 — terraform apply가 덮어쓰지 않도록 방지
  lifecycle {
    ignore_changes = [function_version]
  }
}

# Provisioned Concurrency (prod만 — 콜드 스타트 방지)
resource "aws_lambda_provisioned_concurrency_config" "backend" {
  count = var.provisioned_concurrency > 0 ? 1 : 0

  function_name                     = aws_lambda_function.backend.function_name
  provisioned_concurrent_executions = var.provisioned_concurrency
  qualifier                         = aws_lambda_alias.live.name
}
