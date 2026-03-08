###############################################################################
# WebSocket API Gateway Module
# wss://ws.my-community.shop — WebSocket 연결 관리
#
# Lambda 통합(integration, routes, permission)은 순환 참조 방지를 위해
# 환경 main.tf에서 별도 생성합니다.
###############################################################################

resource "aws_apigatewayv2_api" "websocket" {
  name                       = "${var.project}-${var.environment}-ws"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.type"
}

# -----------------------------------------------------------------------------
# Stage (auto deploy)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.websocket.id
  name        = var.environment
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}

# -----------------------------------------------------------------------------
# Custom Domain (ws.my-community.shop)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_domain_name" "websocket" {
  domain_name = var.ws_domain_name

  domain_name_configuration {
    certificate_arn = var.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = var.tags
}

resource "aws_apigatewayv2_api_mapping" "websocket" {
  api_id      = aws_apigatewayv2_api.websocket.id
  domain_name = aws_apigatewayv2_domain_name.websocket.id
  stage       = aws_apigatewayv2_stage.main.id
}

# Route 53 A 레코드
resource "aws_route53_record" "websocket" {
  zone_id = var.zone_id
  name    = var.ws_domain_name
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.websocket.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.websocket.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
