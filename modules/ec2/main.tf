###############################################################################
# EC2 Module
# Bastion Host (퍼블릭 서브넷, RDS 관리용)
###############################################################################

# 최신 Amazon Linux 2023 AMI (아키텍처는 인스턴스 타입에 따라 선택)
locals {
  # t4g = arm64 (Graviton), 그 외 = x86_64
  ami_arch = startswith(var.instance_type, "t4g") ? "arm64" : "x86_64"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-${local.ami_arch}"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SSH 키페어 (공개키를 변수로 전달)
resource "aws_key_pair" "bastion" {
  count = var.create_bastion && var.ssh_public_key != "" ? 1 : 0

  key_name   = "${var.project}-${var.environment}-bastion-key"
  public_key = var.ssh_public_key

  tags = var.tags
}

# Bastion EC2 인스턴스
resource "aws_instance" "bastion" {
  count = var.create_bastion ? 1 : 0

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.bastion_security_group_id]
  key_name               = var.ssh_public_key != "" ? aws_key_pair.bastion[0].key_name : null

  # MySQL 클라이언트 설치 (RDS 관리용)
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y mariadb105
  EOF

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30 # AL2023 AMI 최소 요구 (Free Tier: 30GB)
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-bastion"
  })
}

# Elastic IP
resource "aws_eip" "bastion" {
  count = var.create_bastion ? 1 : 0

  instance = aws_instance.bastion[0].id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-bastion-eip"
  })
}
