###############################################################################
# EventBridge Module - Outputs
###############################################################################

output "token_cleanup_rule_arn" {
  description = "토큰 정리 스케줄 규칙 ARN"
  value       = aws_cloudwatch_event_rule.token_cleanup.arn
}

output "feed_recompute_rule_arn" {
  description = "피드 재계산 스케줄 규칙 ARN"
  value       = aws_cloudwatch_event_rule.feed_recompute.arn
}
