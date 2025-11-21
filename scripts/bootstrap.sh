#!/bin/bash
set -e

echo "=== Kubernetes Cluster Bootstrap Script ==="

# Get control plane IP from Terraform
CONTROL_PLANE_IP=$(terraform output -raw control_plane_public_ip)
SSH_USER="ubuntu"

echo "Control Plane IP: $CONTROL_PLANE_IP"
echo ""
echo "Waiting for cluster initialization (this may take 5-10 minutes)..."

# Wait for control plane to be ready
MAX_WAIT=600
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $SSH_USER@$CONTROL_PLANE_IP "sudo test -f /etc/kubernetes/admin.conf" 2>/dev/null; then
        echo "✓ Control plane is ready!"
        break
    fi
    echo "Still waiting... ($ELAPSED/$MAX_WAIT seconds)"
    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "✗ Timeout waiting for control plane"
    exit 1
fi

# Get kubeconfig
echo ""
echo "Downloading kubeconfig..."
ssh -o StrictHostKeyChecking=no $SSH_USER@$CONTROL_PLANE_IP "sudo cat /etc/kubernetes/admin.conf" > kubeconfig
sed -i.bak "s|server: https://.*:6443|server: https://$CONTROL_PLANE_IP:6443|" kubeconfig

# Add tls-server-name to kubeconfig
echo "Adding tls-server-name to kubeconfig..."
INTERNAL_IP=$(terraform output -raw control_plane_internal_ip)
yq -i '.clusters[0].cluster.tls-server-name = "'$INTERNAL_IP'"' kubeconfig


echo "✓ Kubeconfig saved to ./kubeconfig"
echo ""

# Check cluster status
echo "Checking cluster status..."
export KUBECONFIG=./kubeconfig

kubectl get nodes
echo ""
kubectl get pods -A
echo ""

# Get ArgoCD password
echo "Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(ssh -o StrictHostKeyChecking=no $SSH_USER@$CONTROL_PLANE_IP "sudo cat /mnt/argocd/admin-password.txt 2>/dev/null" || echo "Not yet available")

# Get ArgoCD NodePort
ARGOCD_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "pending")

echo ""
echo "=== Cluster Ready! ==="
echo ""
echo "Kubeconfig: ./kubeconfig"
echo "Use: export KUBECONFIG=\$(pwd)/kubeconfig"
echo ""
echo "ArgoCD UI: https://$CONTROL_PLANE_IP:$ARGOCD_PORT"
echo "ArgoCD Username: admin"
echo "ArgoCD Password: $ARGOCD_PASSWORD"
echo ""
echo "SSH to control plane: ssh $SSH_USER@$CONTROL_PLANE_IP"
echo ""
