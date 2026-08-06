// variables.tf
// All configurable variables for the Terraform AWS cluster provisioning.

variable "aws_region" {
  description = "AWS region to create resources in"
  type        = string
  default     = "us-east-1"
}

variable "cluster_prefix" {
  description = "Prefix used for naming cluster resources"
  type        = string
  default     = "k8s"
}

variable "environment" {
  description = "Environment tag (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "ssh_key_name" {
  description = "Name for the SSH key pair to create in AWS"
  type        = string
  default     = "k8s-deployer-key"
}

variable "ssh_public_key" {
  description = "Public SSH key material (openssh format). Example: ssh-rsa AAAA... user@host"
  type        = string
  sensitive   = false
  default     = ""
}

variable "ssh_private_key_path" {
  description = "Path to the private key on the machine running Terraform (used in generated inventory)"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_user" {
  description = "SSH user for Ubuntu AMI"
  type        = string
  default     = "ubuntu"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_api_cidrs" {
  description = "CIDR blocks allowed to access Kubernetes API (6443). For production restrict to admin IPs."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "master_instance_type" {
  description = "EC2 instance type for control-plane"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for workers"
  type        = string
  default     = "t3.medium"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1"
  }
}

variable "ami_id" {
  description = "Optional: override AMI id. If empty, Terraform will lookup latest Ubuntu 22.04"
  type        = string
  default     = ""
}
