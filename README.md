# GCP Kubernetes Demo Cluster with kubeadm

Terraform setup for a cost-effective k8s demo cluster that suspends nightly.

## Initial Setup

Before you begin, ensure you have the necessary tools installed and configured:

1.  **Install `gcloud` CLI:** Follow the official Google Cloud documentation to install the `gcloud` command-line tool.
    *   [Install gcloud CLI](https://cloud.google.com/sdk/docs/install)

2.  **Authenticate `gcloud`:** Authenticate your `gcloud` CLI with your GCP account and set up Application Default Credentials.
    ```bash
    gcloud auth login
    gcloud config set project YOUR_PROJECT_ID
    gcloud auth application-default login
    ```
    Replace `YOUR_PROJECT_ID` with your actual GCP project ID.

3.  **Install Terraform:** Download and install Terraform from the official HashiCorp website.
    *   [Install Terraform](https://developer.hashicorp.com/terraform/downloads)

## Architecture

- 1 Control Plane (e2-medium)
- 2 Worker Nodes (e2-medium)
- Cilium for networking
- ArgoCD pre-installed
- Persistent disks for etcd and ArgoCD state
- Auto start/stop scheduling

## Prerequisites

## Architecture

- 1 Control Plane (e2-medium)
- 2 Worker Nodes (e2-medium)
- Cilium for networking
- ArgoCD pre-installed
- Persistent disks for etcd and ArgoCD state
- Auto start/stop scheduling

## Prerequisites

- GCP account with billing enabled
- `gcloud` CLI configured
- Terraform >= 1.0
- SSH key pair

## Quick Start

```bash
# 1. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id and preferences

# 2. Initialize Terraform
terraform init

# 3. Deploy cluster
terraform apply

# 4. Wait for initialization and get kubeconfig
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh

# 5. Use cluster
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

## Accessing the Cluster

### kubectl
```bash
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get pods -A
```

### ArgoCD
```bash
# Get credentials from bootstrap output or:
CONTROL_PLANE_IP=$(terraform output -raw control_plane_public_ip)
ssh ubuntu@$CONTROL_PLANE_IP "sudo cat /mnt/argocd/admin-password.txt"

# Get ArgoCD URL
kubectl get svc argocd-server -n argocd
# Access via https://<CONTROL_PLANE_IP>:<NodePort>
```

### SSH
```bash
# Control plane
terraform output ssh_command_control_plane

# Workers
ssh ubuntu@<worker-public-ip>
```

## VM Scheduling

Default schedule (configurable in terraform.tfvars):
- **Start**: 8 AM weekdays (America/New_York)
- **Stop**: 6 PM weekdays (America/New_York)

Modify `start_schedule` and `stop_schedule` variables:
```hcl
start_schedule = "0 8 * * MON-FRI"  # Cron format
stop_schedule  = "0 18 * * MON-FRI"
timezone       = "America/New_York"
```

## Manual VM Control

```bash
# Stop all VMs
gcloud compute instances stop demo-k8s-control-plane --zone=us-central1-a
gcloud compute instances stop demo-k8s-worker-1 --zone=us-central1-a
gcloud compute instances stop demo-k8s-worker-2 --zone=us-central1-a

# Start all VMs
gcloud compute instances start demo-k8s-control-plane --zone=us-central1-a
gcloud compute instances start demo-k8s-worker-1 --zone=us-central1-a
gcloud compute instances start demo-k8s-worker-2 --zone=us-central1-a
```

## Persistent Data

Data persists across VM stops:
- `/var/lib/etcd` - Kubernetes state
- `/mnt/argocd` - ArgoCD data and admin password


## Cost Estimates

**Active (8 hours/day, 5 days/week)**:
- 3x e2-medium: ~$40/month.  # Note this was changed to e2-standard-4
- Persistent disks: ~$3/month
- Network egress: ~$2-5/month
- **Total**: ~$45-50/month

**If left running 24/7**: ~$150/month

## Troubleshooting

### Check initialization logs
```bash
ssh ubuntu@<control-plane-ip>
sudo tail -f /var/log/k8s-init.log
```

### Re-initialize after issues
```bash
# On control plane
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/etcd/*
# Reboot and let cloud-init re-run
```

### Workers not joining
```bash
# Check worker logs
ssh ubuntu@<worker-ip>
sudo tail -f /var/log/k8s-init.log

# Manual join (get token from control plane)
ssh ubuntu@<control-plane-ip>
sudo kubeadm token create --print-join-command
```

## Cleanup

```bash
terraform destroy
```

## Next Steps

1. Configure ArgoCD to watch your k8s-manifests repo
2. Set up GitHub webhooks for automatic sync
3. Deploy demo applications via GitOps

## Directory Structure

```
infrastructure-gcp/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars
├── scripts/
│   ├── control-plane-init.sh
│   ├── worker-init.sh
│   └── bootstrap.sh
└── README.md
```
