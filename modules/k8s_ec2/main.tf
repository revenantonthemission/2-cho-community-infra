# modules/k8s_ec2/main.tf

# Amazon Linux 2023 최신 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SSH Security Group IDs (조건부)
locals {
  ssh_sg_ids = length(var.allowed_ssh_cidrs) > 0 ? [aws_security_group.k8s_ssh[0].id] : []

  master_sg_ids = concat(
    [aws_security_group.k8s_master.id, aws_security_group.k8s_internal.id],
    local.ssh_sg_ids
  )

  worker_sg_ids = concat(
    [aws_security_group.k8s_worker.id, aws_security_group.k8s_internal.id],
    local.ssh_sg_ids
  )
}

# Master 노드
resource "aws_instance" "master" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.master_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = local.master_sg_ids
  iam_instance_profile   = aws_iam_instance_profile.k8s_node.name
  source_dest_check      = false # Calico Pod 네트워크 직접 라우팅

  user_data = templatefile("${path.module}/userdata.sh", {
    kubernetes_version = var.kubernetes_version
  })

  root_block_device {
    volume_size = var.master_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-master"
    Role = "master"
  })
}

# Master Elastic IP
resource "aws_eip" "master" {
  instance = aws_instance.master.id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-master-eip"
  })
}

# Worker 노드 (2대)
resource "aws_instance" "worker" {
  count = 2

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.worker_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  vpc_security_group_ids = local.worker_sg_ids
  iam_instance_profile   = aws_iam_instance_profile.k8s_node.name
  source_dest_check      = false # Calico Pod 네트워크 직접 라우팅

  user_data = templatefile("${path.module}/userdata.sh", {
    kubernetes_version = var.kubernetes_version
  })

  root_block_device {
    volume_size = count.index == 0 ? var.worker1_volume_size : var.worker2_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-worker-${count.index + 1}"
    Role = "worker"
  })
}
