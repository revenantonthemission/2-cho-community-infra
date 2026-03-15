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
  count = var.master_count

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.master_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
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
    Name = "${var.project}-${var.environment}-k8s-master-${count.index + 1}"
    Role = "master"
  })
}

# Master Elastic IP
resource "aws_eip" "master" {
  count = var.master_count

  instance = aws_instance.master[count.index].id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-master-${count.index + 1}-eip"
  })
}

# Worker 노드
resource "aws_instance" "worker" {
  count = var.worker_count

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
    volume_size = var.worker_volume_sizes[min(count.index, length(var.worker_volume_sizes) - 1)]
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-worker-${count.index + 1}"
    Role = "worker"
  })
}

# Worker Elastic IP
resource "aws_eip" "worker" {
  count = var.worker_count

  instance = aws_instance.worker[count.index].id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-worker-${count.index + 1}-eip"
  })
}

# =============================================================================
# HAProxy Load Balancer (HA Master 전용)
# =============================================================================
resource "aws_instance" "haproxy" {
  count = var.haproxy_enabled ? 1 : 0

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.haproxy_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = var.public_subnet_ids[0]
  iam_instance_profile   = aws_iam_instance_profile.k8s_node.name

  vpc_security_group_ids = concat(
    var.haproxy_enabled ? [aws_security_group.k8s_haproxy[0].id] : [],
    [aws_security_group.k8s_internal.id],
    length(var.allowed_ssh_cidrs) > 0 ? [aws_security_group.k8s_ssh[0].id] : []
  )

  user_data = templatefile("${path.module}/haproxy_userdata.sh", {
    master_backends = join("\n", [
      for idx, inst in aws_instance.master :
      "    server master-${idx + 1} ${inst.private_ip}:6443 check check-ssl verify none"
    ])
  })

  # AL2023 AMI 최소 루트 볼륨 30GB 필요
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-haproxy"
    Role = "haproxy"
  })
}

resource "aws_eip" "haproxy" {
  count = var.haproxy_enabled ? 1 : 0

  instance = aws_instance.haproxy[0].id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-haproxy-eip"
  })
}
