#!/bin/bash

# Setting IP and DNS names for each server !Change it for your env! You can add more worker nodes if you need!
MASTER_IP="10.10.10.1"
WORKER_IP="10.10.10.2"
MASTER_DNS="k8s-master"
WORKER_DNS="k8s-worker"

# Checking the role of the node (master or worker)
if [ "$1" == "master" ]; then
  HOSTNAME=$MASTER_DNS
elif [ "$1" == "worker" ]; then
  HOSTNAME=$WORKER_DNS
else
  echo "Please specify 'master' or 'worker' as an argument."
  exit 1
fi

echo "Setting up the hostname as $HOSTNAME"
sudo hostnamectl set-hostname $HOSTNAME

echo "Updating /etc/hosts"
sudo tee -a /etc/hosts <<EOF
$MASTER_IP $MASTER_DNS
$WORKER_IP $WORKER_DNS
EOF

# Updating the system
echo "Updating the system"
sudo apt-get update && sudo apt-get upgrade -y

# Disabling swap
echo "Disabling swap"
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Setting up kernel parameters
echo "Setting up kernel parameters"
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

# Installing Containerd
echo "Installing containerd"
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt update
sudo apt install -y containerd.io

sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

# Installing Kubernetes components
echo "Installing Kubernetes components"
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Initializing or joining the cluster
if [ "$1" == "master" ]; then
  echo "Initializing Kubernetes master node"
  sudo kubeadm init --apiserver-advertise-address=$MASTER_IP

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  echo "Deploying Calico network"
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml

  echo "Master node setup complete!"
#elif [ "$1" == "worker" ]; then
#  echo "Joining worker node to the cluster"
#  sudo kubeadm join $MASTER_IP:6443 --token <your_token> --discovery-token-ca-cert-hash sha256:<your_hash>
fi
