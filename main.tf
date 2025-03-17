terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = {
      "managed_by" = "terraform",
      "region"     = "ap-south-1",
      "project"    = "ec2-instance-connect"
    }
  }
}

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Create a private subnet
resource "aws_subnet" "my_private_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "ap-south-1a" # Update to your preferred AZ
  map_public_ip_on_launch = false
}
#! Debug
output "default_vpc_id" {
  value = aws_vpc.my_vpc.id
}

output "vpc_subnet_id" {
  value = aws_subnet.my_private_subnet.id
}
#!

# Get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "is-public"
    values = ["true"]
  }

  filter {
    name   = "block-device-mapping.volume-type"
    values = ["gp2"]
  }
}

#! Debug
output "ami-id" {
  value       = data.aws_ami.amazon_linux_2.id
  description = "ami id of latest amazon linux 2 in ap-south-1"
}

output "ami-vol_type" {
  value       = one(data.aws_ami.amazon_linux_2.block_device_mappings).ebs.volume_type
  description = "ami vol type"
}
#!

resource "aws_security_group" "ssm_example_sg" {
  name   = "ssm-example-sg"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    description     = "SSH from connect endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.endpoint_sg.id]
  }
}

resource "aws_instance" "ssm_example_instance" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t4g.micro"
  # For IMDv2
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # network config
  subnet_id              = aws_subnet.my_private_subnet.id
  vpc_security_group_ids = [aws_security_group.ssm_example_sg.id]
}

resource "aws_security_group" "endpoint_sg" {
  name   = "endpoint-sg"
  vpc_id = aws_vpc.my_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ec2_instance_connect_endpoint" "my_endpoint" {
  preserve_client_ip = true
  subnet_id          = aws_subnet.my_private_subnet.id
  security_group_ids = [aws_security_group.endpoint_sg.id]
}
