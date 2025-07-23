provider "aws" {
  region = "us-west-2"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "poc-vpc"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
}

# Private Subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "poc-igw"
  }
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

resource "aws_security_group" "nat_sg" {
  name        = "nat-sg"
  description = "Security group for NAT instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nat-sg"
  }
}

resource "aws_security_group" "nginx_sg" {
  name        = "nginx-sg"
  description = "Security group for NGINX instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nginx-sg"
  }
}

# Data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# NAT Instance
resource "aws_instance" "nat" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.nat_sg.id]
  associate_public_ip_address = true
  source_dest_check           = false
  key_name                    = "aws-key" # Using the user's existing key pair in AWS

  user_data = <<-EOF
              #!/bin/bash
              echo 1 > /proc/sys/net/ipv4/ip_forward
              iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              yum install -y iptables-services
              service iptables save
              EOF

  tags = {
    Name = "nat-instance"
  }
}

# Route table for private subnet (routes through NAT instance)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Bastion Host
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  key_name                    = "aws-key" # Using the user's existing key pair in AWS

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y google-authenticator
              sudo -u ec2-user google-authenticator -t -d -f -r 3 -R 30 -W
              echo "Google Authenticator QR code for initial setup has been generated."
              echo "SSH into the bastion host as ec2-user and follow the prompts to scan the QR code with Google Authenticator app." > /home/ec2-user/authenticator_instructions.txt
              sudo chown ec2-user:ec2-user /home/ec2-user/authenticator_instructions.txt
              sudo sed -i 's|PasswordAuthentication yes|PasswordAuthentication no|g' /etc/ssh/sshd_config
              sudo sed -i 's|ChallengeResponseAuthentication no|ChallengeResponseAuthentication yes|g' /etc/ssh/sshd_config
              sudo systemctl restart sshd
              EOF

  tags = {
    Name = "bastion-host"
  }
}

# NGINX EC2 Instance
resource "aws_instance" "nginx" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.nginx_sg.id]
  associate_public_ip_address = false
  key_name                    = "aws-key" # Using the user's existing key pair in AWS

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo amazon-linux-extras install nginx1 -y
              sudo systemctl start nginx
              sudo systemctl enable nginx
              echo "<html><body><h1>Hello from NGINX!</h1></body></html>" > /usr/share/nginx/html/index.html
              EOF

  tags = {
    Name = "nginx-demo"
  }
}

# Outputs
output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "nat_public_ip" {
  description = "Public IP of the NAT instance"
  value       = aws_instance.nat.public_ip
}

output "nginx_private_ip" {
  description = "Private IP of the NGINX instance"
  value       = aws_instance.nginx.private_ip
}

output "google_authenticator_instructions" {
  description = "Instructions for Google Authenticator setup"
  value       = "SSH into the bastion host at ${aws_instance.bastion.public_ip} as ec2-user. Follow the instructions in /home/ec2-user/authenticator_instructions.txt to scan the QR code with Google Authenticator app for initial setup."
}
