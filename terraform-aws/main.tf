terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  region = var.aws_region
}

data "aws_route53_zone" "metal" {
  name  = "${var.base_domain}."
}

resource "aws_vpc" "metal" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "metal"
  }
}

resource "aws_subnet" "metal" {
  vpc_id = aws_vpc.metal.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name = "metal"
  }
}

resource "aws_internet_gateway" "metaligw" {
  vpc_id = aws_vpc.metal.id
  tags = {
    Name = "metal"
  }
}

resource "aws_route" "metal_default_igw" {
  route_table_id = aws_vpc.metal.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.metaligw.id
}

resource "aws_instance" "metal_gw" {
  ami = var.fedora_amis[var.aws_region]
  subnet_id = aws_subnet.metal.id
  instance_type = "t2.small"
  vpc_security_group_ids = [aws_security_group.metal_sg.id]
  key_name = aws_key_pair.access.key_name

  tags = {
    Name = "MetalGateway"
  }
}

resource "aws_eip" "metal_gw" {
  instance = aws_instance.metal_gw.id
  vpc = true
}

resource "aws_route53_record" "star_metal" {
  zone_id = data.aws_route53_zone.metal.zone_id
  name = "*.metal.${data.aws_route53_zone.metal.name}"
  type = "A"
  ttl = "120"
  records = [aws_eip.metal_gw.public_ip]
}

resource "aws_security_group" "metal_sg" {
  name = "metal gateway ingress"
  description = "Allow SSH and HTTP/HTTPS"
  vpc_id = aws_vpc.metal.id
  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "http"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "https-443"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "https-6443"
    from_port = 6443
    to_port = 6443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "allow all"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "tls_private_key" "ssh_key_pair" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "aws_key_pair" "access" {
  key_name = "metalgw"
  public_key = chomp(tls_private_key.ssh_key_pair.public_key_openssh)
}

resource "local_file" "metal_gw_private_key_pem" {
  content   = chomp(tls_private_key.ssh_key_pair.private_key_pem)
  filename  = "id_rsa_metalgw"
  file_permission = "0600"
}

resource "local_file" "metal_gw_public_key" {
  content   = chomp(tls_private_key.ssh_key_pair.public_key_openssh)
  filename  = "id_rsa_metalgw.pub"
  file_permission = "0600"
}
