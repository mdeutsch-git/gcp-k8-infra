# Copy this file to terraform.tfvars and update with your values

project_id = "sandbox-475916"
region     = "us-central1"
zone       = "us-central1-a"

cluster_name = "gcp-demo-k8s"

# Network CIDRs
subnet_cidr  = "10.0.0.0/24"
pod_cidr     = "10.244.0.0/16"
service_cidr = "10.96.0.0/12"

# Machine types
control_plane_machine_type = "e2-standard-4"
worker_machine_type        = "e2-standard-4"
worker_count               = 2

# SSH
ssh_user             = "ubuntu"
ssh_public_key_path  = "~/.ssh/id_rsa.pub"

# VM Schedules (Cron format in specified timezone)
# Stop at 10 PM weekdays
stop_schedule  = "0 22 * * *"
# Start at 9 AM weekdays  
start_schedule = "0 9 * * MON-FRI"
timezone       = "America/New_York"
