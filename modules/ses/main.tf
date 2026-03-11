# modules/ses/main.tf
# SES 도메인 인증 + DKIM 설정

# -----------------------------------------------------------------------------
# SES Domain Identity (도메인 소유 검증)
# -----------------------------------------------------------------------------
resource "aws_ses_domain_identity" "this" {
  domain = var.domain_name
}

# Route 53 TXT 레코드: SES 도메인 소유 검증
resource "aws_route53_record" "ses_verification" {
  zone_id = var.zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.this.verification_token]
}

resource "aws_ses_domain_identity_verification" "this" {
  domain     = aws_ses_domain_identity.this.id
  depends_on = [aws_route53_record.ses_verification]
}

# -----------------------------------------------------------------------------
# DKIM (이메일 위변조 방지, 스팸 분류 방지)
# -----------------------------------------------------------------------------
resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

# Route 53 CNAME 레코드: DKIM 서명 검증 (3개)
resource "aws_route53_record" "dkim" {
  count   = 3
  zone_id = var.zone_id
  name    = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"]
}
