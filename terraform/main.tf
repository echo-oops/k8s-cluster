// main.tf
// Terraform configuration to provision a small 3-node Kubernetes cluster (1 control-plane, 2 workers)
// on AWS EC2. Instances are Ubuntu 22.04 and are bootstrapped with a cloud-init script that prepares
// the node for later Ansible provisioning (disables swap in cloud-init, installs containerd, enables SSH).
// This module is intentionally opinionated for on-prem-like small clusters on AWS. Adjust variables as needed.

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Credentials are read from environment (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) or shared config.
}

resource "random_pet" "cluster_name" {
  length    = 2
  separator = "-"
}

locals {
  cluster_name = "${var.cluster_prefix}-${random_pet.cluster_name.id}"
  common_tags  = {
    "Name"        = local.cluster_name
    "Project"     = "k8s-cluster"
    "Environment" = var.environment
  }
}

# Create a VPC (minimal) if not using an existing one
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { "component" = "vpc" })
}

resource "aws_subnet" "k8s_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { "component" = "subnet" })
}

data "aws_availability_zones" "available" {}

# Internet gateway and route table for public access (for NodePort/Ingress testing)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.k8s_vpc.id
  tags   = merge(local.common_tags, { "component" = "igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.k8s_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(local.common_tags, { "component" = "route-table" })
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.k8s_subnet.id
  route_table_id = aws_route_table.public.id
}

# Security group allowing SSH, Kubernetes control plane, NodePort range, and DNS/HTTP for testing
resource "aws_security_group" "k8s_sg" {
  name        = "${local.cluster_name}-sg"
  description = "Security group for k8s cluster nodes"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.allowed_api_cidrs
  }

  ingress {
    description = "NodePort range (for ingress testing)"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "etcd (peer) - optional internal"
    from_port   = 2380
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { "component" = "security-group" })
}

# Create or import SSH key pair
resource "aws_key_pair" "deployer_key" {
  key_name   = var.ssh_key_name
  public_key = var.ssh_public_key
  tags       = merge(local.common_tags, { "component" = "ssh-key" })
}

# Cloud-init user data to prepare nodes for Ansible/kubeadm
data "template_file" "cloud_init" {
  template = file("${path.module}/cloud-init/cloud-init.tpl")
  vars = {
    user_name = var.ssh_user
    disable_swap = true
  }
}

# AMI lookup for Ubuntu 22.04 LTS (Canonical)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Control plane instance
resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.k8s_subnet.id
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  associate_public_ip_address = true
  user_data              = data.template_file.cloud_init.rendered
  tags                   = merge(local.common_tags, { "Name" = "${local.cluster_name}-master" })

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }
}

# Worker instances
resource "aws_instance" "workers" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.k8s_subnet.id
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  associate_public_ip_address = true
  user_data              = data.template_file.cloud_init.rendered
  tags                   = merge(local.common_tags, { "Name" = "${local.cluster_name}-worker-${count.index + 1}" })

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }
}

# Optional: Elastic IP for master to have stable controlPlaneEndpoint
resource "aws_eip" "master_eip" {
  instance = aws_instance.master.id
  vpc      = true
  tags     = merge(local.common_tags, { "Name" = "${local.cluster_name}-master-eip" })
}

# Generate an inventory file for Ansible (local file)
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/ansible_inventory.tpl", {
    master_public_ip = aws_eip.master_eip.public_ip
    master_private_ip = aws_instance.master.private_ip
    worker_public_ips = aws_instance.workers.*.public_ip
    worker_private_ips = aws_instance.workers.*.private_ip
    ssh_user = var.ssh_user
    ssh_private_key_path = var.ssh_private_key_path
  })
  filename = "${path.module}/ansible_inventory_generated.ini"
}

# Outputs for convenience
output "master_public_ip" {
  description = "Public IP of the control-plane (master) node"
  value       = aws_eip.master_eip.public_ip
}

output "master_private_ip" {
  description = "Private IP of the control-plane (master) node"
  value       = aws_instance.master.private_ip
}

output "worker_public_ips" {
  description = "Public IPs of worker nodes"
  value       = aws_instance.workers.*.public_ip
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes"
  value       = aws_instance.workers.*.private_ip
}

output "ansible_inventory_path" {
  description = "Path to the generated Ansible inventory file (on the machine where Terraform ran)"
  value       = local_file.ansible_inventory.filename
}
