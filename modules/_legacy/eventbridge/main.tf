###############################################################################
# EventBridge Module
# 배치 작업 스케줄 (토큰 정리, 피드 점수 재계산)
# EventBridge → API Destination → API Gateway HTTP endpoint 호출
###############################################################################

# -----------------------------------------------------------------------------
# API Connection (X-Internal-Key 헤더 인증)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_connection" "internal_api" {
  name               = "${var.project}-${var.environment}-internal-api"
  description        = "내부 API 인증 (X-Internal-Key 헤더)"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "X-Internal-Key"
      value = var.internal_api_key
    }
  }
}

# -----------------------------------------------------------------------------
# API Destinations (엔드포인트별 대상)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_api_destination" "token_cleanup" {
  name                             = "${var.project}-${var.environment}-token-cleanup"
  description                      = "만료 토큰 정리 엔드포인트"
  invocation_endpoint              = "${var.api_endpoint}/v1/admin/cleanup/tokens"
  http_method                      = "POST"
  invocation_rate_limit_per_second = 1
  connection_arn                   = aws_cloudwatch_event_connection.internal_api.arn
}

resource "aws_cloudwatch_event_api_destination" "feed_recompute" {
  name                             = "${var.project}-${var.environment}-feed-recompute"
  description                      = "추천 피드 점수 재계산 엔드포인트"
  invocation_endpoint              = "${var.api_endpoint}/v1/admin/feed/recompute"
  http_method                      = "POST"
  invocation_rate_limit_per_second = 1
  connection_arn                   = aws_cloudwatch_event_connection.internal_api.arn
}

# -----------------------------------------------------------------------------
# 스케줄 규칙
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "token_cleanup" {
  name                = "${var.project}-${var.environment}-token-cleanup"
  description         = "만료 토큰 정리 (1시간마다)"
  schedule_expression = "rate(1 hour)"

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "feed_recompute" {
  name                = "${var.project}-${var.environment}-feed-recompute"
  description         = "추천 피드 점수 재계산 (30분마다)"
  schedule_expression = "rate(30 minutes)"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 타겟 (스케줄 → API Destination)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_target" "token_cleanup" {
  rule      = aws_cloudwatch_event_rule.token_cleanup.name
  target_id = "${var.project}-${var.environment}-token-cleanup"
  arn       = aws_cloudwatch_event_api_destination.token_cleanup.arn
  role_arn  = aws_iam_role.eventbridge.arn
}

resource "aws_cloudwatch_event_target" "feed_recompute" {
  rule      = aws_cloudwatch_event_rule.feed_recompute.name
  target_id = "${var.project}-${var.environment}-feed-recompute"
  arn       = aws_cloudwatch_event_api_destination.feed_recompute.arn
  role_arn  = aws_iam_role.eventbridge.arn
}

# -----------------------------------------------------------------------------
# IAM Role (EventBridge → API Destination 호출 권한)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "eventbridge" {
  name = "${var.project}-${var.environment}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "eventbridge_invoke" {
  name = "${var.project}-${var.environment}-eventbridge-invoke"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "events:InvokeApiDestination"
        Resource = [
          aws_cloudwatch_event_api_destination.token_cleanup.arn,
          aws_cloudwatch_event_api_destination.feed_recompute.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_invoke" {
  role       = aws_iam_role.eventbridge.name
  policy_arn = aws_iam_policy.eventbridge_invoke.arn
}
