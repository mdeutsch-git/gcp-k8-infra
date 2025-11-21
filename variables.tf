variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "demo-k8s"
}

variable "subnet_cidr" {
  description = "Subnet CIDR"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pod_cidr" {
  description = "Pod network CIDR"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service network CIDR"
  type        = string
  default     = "10.96.0.0/12"
}

variable "control_plane_ip" {
  description = "Static internal IP for control plane"
  type        = string
  default     = "10.0.0.10"
}

variable "control_plane_machine_type" {
  description = "Machine type for control plane"
  type        = string
  default     = "e2-medium"
}

variable "worker_machine_type" {
  description = "Machine type for workers"
  type        = string
  default     = "e2-medium"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "ssh_user" {
  description = "SSH user"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "stop_schedule" {
  description = "Cron schedule to stop VMs (format: '0 18 * * *')"
  type        = string
  default     = "0 18 * * MON-FRI"
}

variable "start_schedule" {
  description = "Cron schedule to start VMs (format: '0 8 * * *')"
  type        = string
  default     = "0 8 * * MON-FRI"
}

variable "timezone" {
  description = "Timezone for schedules"
  type        = string
  default     = "America/New_York"
}

variable "cilium_version" {
  description = "Cilium version to install"
  type        = string
  default     = "1.16.5"
}