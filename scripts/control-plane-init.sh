#!/bin/bash
set -e

# Variables from Terraform
POD_CIDR="${pod_cidr}"
SERVICE_CIDR="${service_cidr}"
CONTROL_PLANE_IP="${control_plane_ip}"
CLUSTER_NAME="${cluster_name}"

# Log everything
exec > >(tee /var/log/k8s-init.log)
exec 2>&1

echo "Starting control plane initialization..."

# Wait for network
sleep 10

# Mount persistent disks
mkdir -p /var/lib/etcd
mkdir -p /mnt/argocd

# Check if etcd disk is already formatted
if ! blkid /dev/disk/by-id/google-etcd; then
    mkfs.ext4 -F /dev/disk/by-id/google-etcd
fi
if ! blkid /dev/disk/by-id/google-argocd; then
    mkfs.ext4 -F /dev/disk/by-id/google-argocd
fi

# Add to fstab if not already there
if ! grep -q "/var/lib/etcd" /etc/fstab; then
    echo "/dev/disk/by-id/google-etcd /var/lib/etcd ext4 defaults 0 0" >> /etc/fstab
fi
if ! grep -q "/mnt/argocd" /etc/fstab; then
    echo "/dev/disk/by-id/google-argocd /mnt/argocd ext4 defaults 0 0" >> /etc/fstab
fi

mount -a

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

# Check if cluster is already initialized
if [ ! -f /etc/kubernetes/admin.conf ]; then
    echo "Initializing Kubernetes cluster..."
    
    kubeadm init \
        --pod-network-cidr=$POD_CIDR \
        --service-cidr=$SERVICE_CIDR \
        --apiserver-advertise-address=$CONTROL_PLANE_IP \
        --apiserver-cert-extra-sans=$CONTROL_PLANE_IP \
        --node-name=$(hostname) \
        --ignore-preflight-errors=NumCPU,DirAvailable--var-lib-etcd

    # Setup kubeconfig for root
    export KUBECONFIG=/etc/kubernetes/admin.conf
    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /root/.bashrc

    # Setup kubeconfig for ubuntu user
    mkdir -p /home/ubuntu/.kube
    cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    chown -R ubuntu:ubuntu /home/ubuntu/.kube

    # Install Calico
    echo "Installing Calico..."
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

    # Wait for Calico to be ready
    echo "Waiting for Calico pods..."
    kubectl wait --for=condition=ready pod -l k8s-app=calico-kube-controllers -n kube-system --timeout=300s || true
    sleep 30

    # Generate join command
    kubeadm token create --print-join-command > /tmp/kubeadm-join-command.sh
    chmod +x /tmp/kubeadm-join-command.sh
    
    # Store join command in GCP metadata for workers to retrieve
    JOIN_COMMAND=$(cat /tmp/kubeadm-join-command.sh)
    gcloud compute project-info add-metadata --metadata k8s-join-command="$JOIN_COMMAND"

    echo "Control plane initialization complete!"
else
    echo "Cluster already initialized, skipping init..."
fi

# Install ArgoCD on first boot only
if [ ! -f /mnt/argocd/.installed ]; then
    echo "Installing ArgoCD..."
    export KUBECONFIG=/etc/kubernetes/admin.conf
    
    # Wait for API server
    sleep 30
    
    # Create ArgoCD namespace
    kubectl create namespace argocd || true
    
    # Install ArgoCD
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    
    # Get initial admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo "ArgoCD Admin Password: $ARGOCD_PASSWORD" > /mnt/argocd/admin-password.txt
    
    # Patch ArgoCD server for NodePort
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
    
    touch /mnt/argocd/.installed
    echo "ArgoCD installation complete!"
fi

echo "Setup complete! Join command available at /tmp/kubeadm-join-command.sh"