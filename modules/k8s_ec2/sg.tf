# modules/k8s_ec2/sg.tf

# K8s Master 노드 Security Group
resource "aws_security_group" "k8s_master" {
  name_prefix = "${var.project}-${var.environment}-k8s-master-"
  description = "K8s master node - API server, etcd, kubelet"
  vpc_id      = var.vpc_id

  # API Server (관리자 IP + 노드 간 통신은 k8s_internal SG에서 처리)
  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # etcd (Master 자체 + 다른 Master)
  ingress {
    description = "etcd server client API"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  # kubelet API
  ingress {
    description = "kubelet API"
    from_port   = 10250
    to_port     = 10252
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-master"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# K8s Worker 노드 Security Group
resource "aws_security_group" "k8s_worker" {
  name_prefix = "${var.project}-${var.environment}-k8s-worker-"
  description = "K8s worker node - kubelet, NodePort, Ingress"
  vpc_id      = var.vpc_id

  # kubelet API
  ingress {
    description     = "kubelet API"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_master.id]
  }

  # HTTP (Ingress Controller hostNetwork)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (Ingress Controller hostNetwork)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-worker"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# K8s 노드 간 Internal 통신 Security Group
resource "aws_security_group" "k8s_internal" {
  name_prefix = "${var.project}-${var.environment}-k8s-internal-"
  description = "K8s inter-node communication - Pod network"
  vpc_id      = var.vpc_id

  # 노드 간 전체 허용 (Calico Pod 네트워크)
  ingress {
    description = "All inter-node traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-internal"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# SSH 접근 Security Group
resource "aws_security_group" "k8s_ssh" {
  count = length(var.allowed_ssh_cidrs) > 0 ? 1 : 0

  name_prefix = "${var.project}-${var.environment}-k8s-ssh-"
  description = "SSH access to K8s nodes"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k8s-ssh"
  })

  lifecycle {
    create_before_destroy = true
  }
}
