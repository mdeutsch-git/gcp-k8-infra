output "control_plane_public_ip" {
  description = "Public IP of control plane"
  value       = google_compute_instance.control_plane.network_interface[0].access_config[0].nat_ip
}

output "control_plane_internal_ip" {
  description = "Internal IP of control plane"
  value       = google_compute_instance.control_plane.network_interface[0].network_ip
}

output "worker_public_ips" {
  description = "Public IPs of worker nodes"
  value       = [for instance in google_compute_instance.workers : instance.network_interface[0].access_config[0].nat_ip]
}

output "worker_internal_ips" {
  description = "Internal IPs of worker nodes"
  value       = [for instance in google_compute_instance.workers : instance.network_interface[0].network_ip]
}

output "ssh_command_control_plane" {
  description = "SSH command for control plane"
  value       = "ssh ${var.ssh_user}@${google_compute_instance.control_plane.network_interface[0].access_config[0].nat_ip}"
}

output "kubeconfig_command" {
  description = "Command to get kubeconfig"
  value       = "ssh ${var.ssh_user}@${google_compute_instance.control_plane.network_interface[0].access_config[0].nat_ip} 'sudo cat /etc/kubernetes/admin.conf' > kubeconfig && sed -i 's/server: https:\\/\\/.*/server: https:\\/\\/${google_compute_instance.control_plane.network_interface[0].access_config[0].nat_ip}:6443/' kubeconfig"
}
