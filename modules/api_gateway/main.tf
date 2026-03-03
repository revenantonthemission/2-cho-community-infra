###############################################################################
# API Gateway Module
# HTTP API → Lambda 통합 + 커스텀 도메인
###############################################################################

# -----------------------------------------------------------------------------
# Access Log Group (순환 참조 방지를 위해 이 모듈에서 직접 생성)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "access_logs" {
  name              = "/aws/apigateway/${var.project}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# -----------------------------------------------------------------------------
# HTTP API (REST API보다 저렴하고 빠름)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "this" {
  name          = "${var.project}-${var.environment}-api"
  protocol_type = "HTTP"

  # CORS: allow_credentials=true 시 allow_origins에 와일드카드 사용 불가
  cors_configuration {
    allow_origins     = var.cors_allowed_origins
    allow_methods     = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers     = ["Content-Type", "Authorization"]
    allow_credentials = true
    max_age           = 3600
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-api"
  })
}

# -----------------------------------------------------------------------------
# Lambda Integration
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "lambda" {
  api_id = aws_apigatewayv2_api.this.id

  integration_type   = "AWS_PROXY"
  integration_uri    = var.lambda_invoke_arn
  integration_method = "POST"

  # Lambda로 전체 요청 전달 (payload format 2.0)
  payload_format_version = "2.0"
}

# 모든 요청을 Lambda로 라우팅 ($default catch-all)
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Lambda 호출 권한 (API Gateway → Lambda)
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvokeAlias"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  qualifier     = var.lambda_alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"

  # statement_id 변경으로 인한 recreate 시 기존 permission 삭제 전 새 permission 생성
  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Stage (자동 배포)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access_logs.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      protocol         = "$context.protocol"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Custom Domain (my-community.shop의 API 서브도메인)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_domain_name" "this" {
  domain_name = var.api_domain_name

  domain_name_configuration {
    certificate_arn = var.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = var.tags
}

resource "aws_apigatewayv2_api_mapping" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this.id
  stage       = aws_apigatewayv2_stage.this.id
}

# Route 53 레코드: API 도메인 → API Gateway
resource "aws_route53_record" "api" {
  zone_id = var.zone_id
  name    = var.api_domain_name
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.this.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.this.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
