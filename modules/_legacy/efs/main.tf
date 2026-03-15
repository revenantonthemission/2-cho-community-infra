###############################################################################
# EFS Module
# 업로드 파일 저장소 (Lambda에 마운트)
###############################################################################

resource "aws_efs_file_system" "this" {
  creation_token = "${var.project}-${var.environment}-uploads"
  encrypted      = true

  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-uploads"
  })
}

# 각 프라이빗 서브넷에 마운트 타겟 생성 (Lambda가 어느 AZ에서든 접근 가능)
resource "aws_efs_mount_target" "this" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [var.efs_security_group_id]
}

# Lambda용 액세스 포인트 (경로 + POSIX 사용자 설정)
resource "aws_efs_access_point" "lambda" {
  file_system_id = aws_efs_file_system.this.id

  # Lambda가 접근할 루트 디렉토리
  root_directory {
    path = "/uploads"

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  # Lambda 실행 시 POSIX 사용자
  posix_user {
    gid = 1000
    uid = 1000
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-lambda-ap"
  })
}

# EFS 수명 주기 정책: 접근하지 않는 파일을 IA(Infrequent Access)로 이동 (비용 절감)
resource "aws_efs_file_system_policy" "this" {
  file_system_id = aws_efs_file_system.this.id

  # 전송 중 암호화 강제 + 액세스 포인트 경유 마운트 허용
  # Principal "*"는 IAM 정책 + VPC 보안 그룹으로 이미 제한됨
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceEncryptInTransit"
        Effect    = "Deny"
        Principal = "*"
        Action    = "*"
        Resource  = aws_efs_file_system.this.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "AllowMountViaAccessPoint"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = aws_efs_file_system.this.arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = aws_efs_access_point.lambda.arn
          }
        }
      }
    ]
  })
}
