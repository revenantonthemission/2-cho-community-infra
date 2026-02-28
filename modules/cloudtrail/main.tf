###############################################################################
# CloudTrail Module
# API 호출 감사 로그
###############################################################################

# CloudTrail 전용 CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# CloudTrail → CloudWatch Logs 전달용 IAM Role
resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${var.project}-${var.environment}-cloudtrail-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "cloudtrail-cloudwatch-logs"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}

resource "aws_cloudtrail" "this" {
  name                          = "${var.project}-${var.environment}-trail"
  s3_bucket_name                = var.cloudtrail_s3_bucket_id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  # 자체 생성한 CloudTrail 전용 로그 그룹 사용
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  # 관리 이벤트 로깅
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-trail"
  })
}
