#!/bin/bash
set -euxo pipefail

# 변수 (Terraform templatefile로 주입)
K8S_VERSION="${kubernetes_version}"

# 1. 커널 모듈 로드
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 2. sysctl 설정
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# 3. swap 비활성화
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# 4. containerd 설치
dnf install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
# SystemdCgroup 활성화
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# 5. Kubernetes 리포지토리 추가 + kubeadm/kubelet/kubectl 설치
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v$${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v$${K8S_VERSION}/rpm/repodata/repomd.xml.key
EOF

dnf install -y kubelet kubeadm kubectl
systemctl enable kubelet

# 6. crictl 설정 (containerd 소켓)
cat <<EOF | tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

# 7. 데이터 디렉토리 생성 (Worker 노드용)
mkdir -p /data/mysql /data/redis /data/prometheus /data/uploads
chmod 777 /data/mysql /data/redis /data/prometheus /data/uploads

echo "K8s node setup complete. Run kubeadm init (master) or kubeadm join (worker) manually."
