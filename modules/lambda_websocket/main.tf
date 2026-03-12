###############################################################################
# WebSocket Lambda Module
# $connect / $disconnect / $default 핸들러
###############################################################################

# -----------------------------------------------------------------------------
# IAM Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "websocket_lambda" {
  name = "${var.project}-${var.environment}-ws-lambda-role"

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

resource "aws_iam_role_policy_attachment" "ws_lambda_basic" {
  role       = aws_iam_role.websocket_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# DynamoDB 접근 + API Gateway Management API 권한
resource "aws_iam_policy" "ws_lambda_policy" {
  name = "${var.project}-${var.environment}-ws-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query"
        ]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/index/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "execute-api:ManageConnections"
        Resource = var.ws_api_gateway_id != "" ? "arn:aws:execute-api:${var.aws_region}:*:${var.ws_api_gateway_id}/*" : "arn:aws:execute-api:${var.aws_region}:*:*/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ws_lambda_policy" {
  role       = aws_iam_role.websocket_lambda.name
  policy_arn = aws_iam_policy.ws_lambda_policy.arn
}

# SSM 접근 (SECRET_KEY 조회 — JWT 검증용)
resource "aws_iam_policy" "ws_lambda_ssm" {
  name = "${var.project}-${var.environment}-ws-lambda-ssm"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = var.secret_key_ssm_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ws_lambda_ssm" {
  role       = aws_iam_role.websocket_lambda.name
  policy_arn = aws_iam_policy.ws_lambda_ssm.arn
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ws_lambda" {
  name              = "/aws/lambda/${var.project}-${var.environment}-websocket"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Placeholder ZIP (최초 apply용 — CD 파이프라인이 실제 코드를 배포)
# -----------------------------------------------------------------------------
data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/placeholder.zip"

  source {
    content  = "def lambda_handler(event, context): return {'statusCode': 200}"
    filename = "handler.py"
  }
}

# -----------------------------------------------------------------------------
# Lambda Function (ZIP 배포 — 경량 핸들러)
# CD 파이프라인이 aws lambda update-function-code로 실제 코드를 배포하므로
# Terraform은 placeholder로 최초 생성만 담당
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "websocket" {
  function_name = "${var.project}-${var.environment}-websocket"
  role          = aws_iam_role.websocket_lambda.arn

  runtime = "python3.11"
  handler = "handler.lambda_handler"

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  memory_size = 256
  timeout     = 30

  environment {
    variables = {
      DYNAMODB_TABLE      = var.dynamodb_table_name
      SECRET_KEY_SSM_NAME = var.secret_key_ssm_name
      WS_API_ENDPOINT     = var.ws_api_endpoint
      AUTH_TIMEOUT_SEC    = "10"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ws_lambda_basic,
    aws_iam_role_policy_attachment.ws_lambda_policy,
    aws_iam_role_policy_attachment.ws_lambda_ssm,
    aws_cloudwatch_log_group.ws_lambda,
  ]

  # CD 파이프라인이 코드를 관리 — terraform apply가 placeholder로 되돌리지 않도록 방지
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-websocket"
  })
}
