###############################################################################
# CloudWatch Module
# 메트릭 알람, 대시보드
# Note: API Gateway 로그 그룹은 api_gateway 모듈에서 직접 생성 (순환 참조 방지)
###############################################################################

# -----------------------------------------------------------------------------
# Lambda Error Alarm
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project}-${var.environment}-lambda-errors"
  alarm_description   = "Lambda 함수 에러 발생 감지"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# Lambda 실행 시간 알람 (타임아웃 근접 시)
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.project}-${var.environment}-lambda-duration"
  alarm_description   = "Lambda 실행 시간 임계치 초과"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.lambda_duration_threshold_ms

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# -----------------------------------------------------------------------------
# RDS Alarms
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project}-${var.environment}-rds-cpu"
  alarm_description   = "RDS CPU 사용률 높음"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_cpu_threshold

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.project}-${var.environment}-rds-storage"
  alarm_description   = "RDS 여유 스토리지 부족"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_free_storage_threshold_bytes

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# RDS 연결 수 알람
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project}-${var.environment}-rds-connections"
  alarm_description   = "RDS 연결 수 높음"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_connection_threshold

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Dashboard
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title = "Lambda Invocations & Errors"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_name],
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_name],
            ["AWS/Lambda", "Throttles", "FunctionName", var.lambda_function_name]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title = "Lambda Duration"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "Average" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "p99" }]
          ]
          period = 300
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title = "RDS CPU & Connections"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_instance_id]
          ]
          period = 300
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title = "API Gateway Requests"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", var.api_gateway_id],
            ["AWS/ApiGateway", "4xx", "ApiId", var.api_gateway_id],
            ["AWS/ApiGateway", "5xx", "ApiId", var.api_gateway_id]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
        }
      }
    ]
  })
}
