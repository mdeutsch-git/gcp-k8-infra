#!/bin/bash
set -e

# Variables from Terraform
CONTROL_PLANE_IP="${control_plane_ip}"
CLUSTER_NAME="${cluster_name}"

# Log everything
exec > >(tee /var/log/k8s-init.log)
exec 2>&1

echo "Starting worker node initialization..."

# Wait for network
sleep 15

# Update and install dependencies
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg socat conntrack

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Enable kernel modules
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Sysctl params
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Install containerd
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Install kubeadm, kubelet, kubectl
KUBE_VERSION="1.29"
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$KUBE_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBE_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

# Wait for control plane to be ready and join cluster
echo "Waiting for control plane to be ready..."

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Try to get join command from GCP metadata
    JOIN_COMMAND=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items.filter(key:k8s-join-command).firstof(value))" 2>/dev/null)
    
    if [ ! -z "$JOIN_COMMAND" ]; then
        echo "Found join command, joining cluster..."
        
        # Check if already joined
        if [ ! -f /etc/kubernetes/kubelet.conf ]; then
            echo "$JOIN_COMMAND" | bash
            echo "Successfully joined cluster!"
        else
            echo "Already joined to cluster, skipping..."
        fi
        break
    else
        echo "Join command not available yet, retrying in 10s... ($RETRY_COUNT/$MAX_RETRIES)"
        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 10
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "Failed to join cluster after $MAX_RETRIES attempts"
    exit 1
fi

echo "Worker node setup complete!"