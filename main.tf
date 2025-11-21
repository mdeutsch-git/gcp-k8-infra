terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Network
resource "google_compute_network" "k8s_network" {
  name                    = "${var.cluster_name}-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "k8s_subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.k8s_network.id
  region        = var.region
}

# Firewall Rules
resource "google_compute_firewall" "k8s_internal" {
  name    = "${var.cluster_name}-internal"
  network = google_compute_network.k8s_network.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
}

resource "google_compute_firewall" "k8s_api" {
  name    = "${var.cluster_name}-api"
  network = google_compute_network.k8s_network.name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k8s-control-plane"]
}

resource "google_compute_firewall" "ssh" {
  name    = "${var.cluster_name}-ssh"
  network = google_compute_network.k8s_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Persistent Disks
resource "google_compute_disk" "etcd_disk" {
  name = "${var.cluster_name}-etcd-disk"
  type = "pd-ssd"
  zone = var.zone
  size = 20
}

resource "google_compute_disk" "argocd_disk" {
  name = "${var.cluster_name}-argocd-disk"
  type = "pd-standard"
  zone = var.zone
  size = 10
}

# Control Plane Instance
resource "google_compute_instance" "control_plane" {
  name         = "${var.cluster_name}-control-plane"
  machine_type = var.control_plane_machine_type
  zone         = var.zone

  tags = ["k8s-control-plane"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
      type  = "pd-standard"
    }
  }

  attached_disk {
    source      = google_compute_disk.etcd_disk.id
    device_name = "etcd"
  }

  attached_disk {
    source      = google_compute_disk.argocd_disk.id
    device_name = "argocd"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.k8s_subnet.id
    network_ip = var.control_plane_ip

    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
    user-data              = templatefile("${path.module}/scripts/control-plane-init.sh", {
      pod_cidr             = var.pod_cidr
      service_cidr         = var.service_cidr
      control_plane_ip     = var.control_plane_ip
      cluster_name         = var.cluster_name
      cilium_version       = var.cilium_version
    })
  }

  allow_stopping_for_update = true

  service_account {
    scopes = ["cloud-platform"]
  }

  resource_policies = [
    google_compute_resource_policy.vm_schedule.id
  ]
}

# Worker Instances
resource "google_compute_instance" "workers" {
  count        = var.worker_count
  name         = "${var.cluster_name}-worker-${count.index + 1}"
  machine_type = var.worker_machine_type
  zone         = var.zone

  tags = ["k8s-worker"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.k8s_subnet.id

    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys  = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
    user-data = templatefile("${path.module}/scripts/worker-init.sh", {
      control_plane_ip = var.control_plane_ip
      cluster_name     = var.cluster_name
    })
  }

  allow_stopping_for_update = true

  service_account {
    scopes = ["cloud-platform"]
  }

  resource_policies = [
    google_compute_resource_policy.vm_schedule.id
  ]

  depends_on = [google_compute_instance.control_plane]
}

# VM Scheduler - Combined start/stop schedule
resource "google_compute_resource_policy" "vm_schedule" {
  name   = "${var.cluster_name}-schedule"
  region = var.region

  instance_schedule_policy {
    vm_start_schedule {
      schedule = var.start_schedule
    }
    vm_stop_schedule {
      schedule = var.stop_schedule
    }
    time_zone = var.timezone
  }
}