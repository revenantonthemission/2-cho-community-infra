###############################################################################
# DynamoDB Module
# WebSocket 연결 매핑 + Rate Limiter 카운터 테이블
###############################################################################

resource "aws_dynamodb_table" "ws_connections" {
  name         = "${var.project}-${var.environment}-ws-connections"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "connection_id"

  attribute {
    name = "connection_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "N"
  }

  global_secondary_index {
    name            = "user_id-index"
    hash_key        = "user_id"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-ws-connections"
  })
}

# -----------------------------------------------------------------------------
# Rate Limiter 테이블 (Fixed Window Counter)
# PK: rate_key (IP:METHOD:PATH), TTL로 윈도우 만료 시 자동 삭제
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "rate_limit" {
  name         = "${var.project}-${var.environment}-rate-limit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "rate_key"

  attribute {
    name = "rate_key"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-rate-limit"
  })
}
