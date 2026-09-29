# --- DATA SOURCE: AMBIL AMI UBUNTU TERBARU OTOMATIS ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Pemilik Resmi Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- NETWORKING (VPC, Subnet, & Route Table) ---
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "k8s-vpc"
  }
}

resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "k8s-igw"
  }
}

resource "aws_subnet" "k8s_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-subnet"
  }
}

resource "aws_route_table" "k8s_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = {
    Name = "k8s-routetable"
  }
}

resource "aws_route_table_association" "k8s_rta" {
  subnet_id      = aws_subnet.k8s_subnet.id
  route_table_id = aws_route_table.k8s_rt.id
}

# --- FIREWALL (Security Group) ---
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-allow-all-sg"
  description = "Allow ports 1-10000 and K3s UDP for Kubernetes"
  vpc_id      = aws_vpc.k8s_vpc.id

  # Membuka port TCP 1 sampai 10000 (mencakup SSH 22, HTTP 80, HTTPS 443, K3s API 6443, dll)
  ingress {
    description = "Allow TCP ports 1-10000"
    from_port   = 1
    to_port     = 10000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Membuka port UDP 8472 khusus untuk Flannel VXLAN K3s antar node
  ingress {
    description = "K3s Flannel VXLAN UDP"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Mengizinkan seluruh lalu lintas keluar (outbound)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-firewall"
  }
}

# --- COMPUTE (3 Ubuntu Servers + Hostname Automation) ---
locals {
  server_tags      = ["Kubernetes-master", "Kubernetes-worker-1", "Kubernetes-worker-2"]
  server_hostnames = ["master", "worker-1", "worker-2"]
}

resource "aws_instance" "k8s_nodes" {
  count                  = 3
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.k8s_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  key_name               = var.key_name

  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Cloud-Init untuk otomatisasi ubah hostname saat pertama kali booting
  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname "${local.server_hostnames[count.index]}"
              echo "127.0.0.1 ${local.server_hostnames[count.index]}" >> /etc/hosts
              EOF

  tags = {
    Name = local.server_tags[count.index]
    Role = count.index == 0 ? "control-plane" : "worker"
  }
}

# --- STATIC IP (Elastic IP) ---
resource "aws_eip" "k8s_eip" {
  count    = 3
  domain   = "vpc"
  instance = aws_instance.k8s_nodes[count.index].id

  tags = {
    Name = "${local.server_tags[count.index]}-eip"
  }
}

# --- ADDITIONAL BLOCK STORAGE (3 EBS Volumes) ---
resource "aws_ebs_volume" "k8s_storage" {
  count             = 3
  availability_zone = aws_instance.k8s_nodes[0].availability_zone
  size              = 10 
  type              = "gp3"

  tags = {
    Name = "k8s-extra-storage-${local.server_hostnames[count.index]}"
  }
}

# Attach EBS volume 1 ke master
resource "aws_volume_attachment" "ebs_attach_master" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.k8s_storage[0].id
  instance_id = aws_instance.k8s_nodes[0].id
}

# Attach EBS volume 2 ke worker-1
resource "aws_volume_attachment" "ebs_attach_worker1" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.k8s_storage[1].id
  instance_id = aws_instance.k8s_nodes[1].id
}

# Attach EBS volume 3 ke worker-2
resource "aws_volume_attachment" "ebs_attach_worker2" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.k8s_storage[2].id
  instance_id = aws_instance.k8s_nodes[2].id
}