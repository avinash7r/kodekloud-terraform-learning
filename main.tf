terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

########################
# VPC
########################
resource "aws_vpc" "k8s" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "k8s-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.k8s.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.k8s.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.k8s.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "k8s-public-subnet"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

########################
# SECURITY GROUP
########################
resource "aws_security_group" "k8s_master" {
  name        = "k8s-master-sg"
  description = "Kubernetes control plane security group"
  vpc_id      = aws_vpc.k8s.id

  # SSH (restrict this later to your IP)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubernetes API Server
  ingress {
    description = "Kubernetes API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"] # workers
  }

  # etcd
  ingress {
    description = "etcd"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  # kubelet API
  ingress {
    description = "kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  # Internal cluster traffic
  ingress {
    description = "Cluster internal"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.10.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "k8s_worker" {
  name        = "k8s-worker-sg"
  description = "Kubernetes worker nodes security group"
  vpc_id      = aws_vpc.k8s.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # kubelet
  ingress {
    description = "kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  # kube-proxy
  ingress {
    description = "kube-proxy"
    from_port   = 10256
    to_port     = 10256
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  # NodePort Services
  ingress {
    description = "NodePort TCP"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort UDP"
    from_port   = 30000
    to_port     = 32767
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Internal cluster traffic
  ingress {
    description = "Cluster internal"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.10.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

########################
# AMI
########################
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

########################
# EC2 INSTANCES
########################
resource "aws_key_pair" "my_key" {
  key_name = "my-key"
  public_key = file("my-key.pub")
  
}


resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_master.id]
  key_name               = aws_key_pair.my_key.key_name

  tags = {
    Name = "k8s-master"
    Role = "control-plane"
  }
}

resource "aws_instance" "worker" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_worker.id]
  key_name               = aws_key_pair.my_key.key_name

  tags = {
    Name = "k8s-worker-${count.index + 1}"
    Role = "worker"
  }
}

########################
# OUTPUTS
########################
output "master_public_ip" {
  value = aws_instance.master.public_ip
}

output "worker_public_ips" {
  value = aws_instance.worker[*].public_ip
}
