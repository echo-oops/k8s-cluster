// outputs.tf
// Expose useful information after apply.

output "cluster_name" {
  description = "Generated cluster name"
  value       = "${var.cluster_prefix}-${random_pet.cluster_name.id}"
}

output "master_ssh" {
  description = "SSH connection string for master node"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${aws_eip.master_eip.public_ip}"
}

output "master_public_ip" {
  description = "Public IP of master node"
  value       = aws_eip.master_eip.public_ip
}

output "worker_public_ips" {
  description = "Public IPs of worker nodes"
  value       = aws_instance.workers.*.public_ip
}

output "ansible_inventory_file" {
  description = "Path to the generated Ansible inventory file (on the machine where Terraform ran)"
  value       = local_file.ansible_inventory.filename
}
