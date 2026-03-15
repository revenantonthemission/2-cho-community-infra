###############################################################################
# CloudWatch Module - Outputs
###############################################################################

output "dashboard_name" {
  description = "CloudWatch 대시보드 이름"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}
