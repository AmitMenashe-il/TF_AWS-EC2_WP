# Providers
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "3.0.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-1"
}

resource "tls_private_key" "generated_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

data "tls_public_key" "generated_public_key" {
  depends_on = [tls_private_key.generated_key]

  private_key_pem = tls_private_key.generated_key.private_key_pem
}

resource "aws_key_pair" "session_key" {
  key_name   = "session_key"
  public_key = data.tls_public_key.generated_public_key.public_key_openssh
}

data "external" "ip_query" {
  program = ["curl", "-sS", "https://api.ipify.org?format=json"]
}

locals {
  ip_address = data.external.ip_query.result.ip
}

resource "aws_security_group" "security_group" {
  name        = "RunningHostAccess_terraform"
  description = "Allow SSH and port 8000 access"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${local.ip_address}/32"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["${local.ip_address}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#create ubuntu aws server with existing key and created security group
resource "aws_instance" "app_server" {
  ami           = "ami-007855ac798b5175e"
  instance_type = "t2.micro"

  key_name="session_key"

  vpc_security_group_ids = [aws_security_group.security_group.id]

    # copy compose file
  provisioner "file" {
        source      = "docker-compose.yaml"
        destination = "/home/ubuntu/docker-compose.yaml"
       
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.generated_key.private_key_pem
      host        = "${aws_instance.app_server.public_dns}"
    }
  }
  
  # install and run docker
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker docker-compose",
      "sudo docker-compose up -d"
    ]
    
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.generated_key.private_key_pem
      host        = "${aws_instance.app_server.public_dns}"
    }
  }
}

# Output the connection string to the console
output "connection_command" {
  value = "Connect to ${aws_instance.app_server.public_dns}:8000"
}