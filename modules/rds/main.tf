###############################################################################
# RDS Module
# MySQL 데이터베이스 (프라이빗 서브넷)
###############################################################################

# engine_version에서 parameter_group_family를 자동 도출 (불일치 방지)
locals {
  parameter_group_family = "mysql${var.engine_version}"
}

# DB 서브넷 그룹 (Multi-AZ 배치)
resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.environment}-db-subnet"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-db-subnet"
  })
}

# DB 파라미터 그룹 (MySQL 설정 커스터마이징)
resource "aws_db_parameter_group" "this" {
  name   = "${var.project}-${var.environment}-mysql-params"
  family = local.parameter_group_family

  # READ COMMITTED 격리 수준 (애플리케이션과 일치)
  parameter {
    name  = "transaction_isolation"
    value = "READ-COMMITTED"
  }

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-mysql-params"
  })
}

# RDS MySQL 인스턴스
resource "aws_db_instance" "this" {
  identifier = "${var.project}-${var.environment}-mysql"

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.rds_security_group_id]

  multi_az            = var.multi_az
  publicly_accessible = false

  # 백업 설정
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00" # UTC (KST 12:00-13:00)
  maintenance_window      = "sun:04:00-sun:05:00"

  # 삭제 보호
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.project}-${var.environment}-final-snapshot" : null

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-mysql"
  })
}
