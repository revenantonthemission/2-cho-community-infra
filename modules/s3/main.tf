###############################################################################
# S3 Module
# 프론트엔드 정적 웹사이트 호스팅 + CloudTrail 로그 버킷
###############################################################################

# -----------------------------------------------------------------------------
# Frontend Static Website Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project}-${var.environment}-frontend"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-frontend"
  })
}

# S3 Website Hosting 제거 — CloudFront OAC로 접근 제어
# Clean URL 리라이트는 CloudFront Functions에서 처리

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 서버 측 암호화 (비공개 버킷이므로 추가)
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 버킷 정책은 CloudFront 모듈에서 OAC 기반으로 생성
# (순환 의존성 방지: S3 → CloudFront → S3 Policy)

# -----------------------------------------------------------------------------
# CloudTrail Logs Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "${var.project}-${var.environment}-cloudtrail-logs"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-cloudtrail-logs"
  })
}

# CloudTrail 로그는 비공개
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudTrail이 로그를 기록할 수 있도록 버킷 정책
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# 로그 수명 주기: 90일 후 삭제 (비용 관리)
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.cloudtrail_log_retention_days
    }
  }
}

# 서버 측 암호화 (보안 감사 로그이므로 필수)
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------------------------------
# Uploads Bucket (사용자 업로드 이미지: 프로필, 게시글)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = "${var.project}-${var.environment}-uploads"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-uploads"
  })
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = aws_s3_bucket.uploads[0].id

  block_public_acls       = true
  block_public_policy     = false  # 버킷 정책으로 공개 읽기 허용
  ignore_public_acls      = true
  restrict_public_buckets = false  # 공개 읽기 정책 허용
}

# 업로드 파일 공개 읽기 정책 (이미지는 공개 콘텐츠)
resource "aws_s3_bucket_policy" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = aws_s3_bucket.uploads[0].id

  depends_on = [aws_s3_bucket_public_access_block.uploads]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadUploads"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.uploads[0].arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = aws_s3_bucket.uploads[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CORS: 프론트엔드에서 이미지 로드 허용
resource "aws_s3_bucket_cors_configuration" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = aws_s3_bucket.uploads[0].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = var.uploads_cors_origins
    max_age_seconds = 3600
  }
}
