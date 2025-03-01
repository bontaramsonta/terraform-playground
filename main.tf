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
      "project"    = "ssm-example"
    }
  }
}

# Get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Get the default subnets in the default VPC (across all AZs)
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

#! Debug
output "default_vpc_id" {
  value       = data.aws_vpc.default.id
  description = "default vpc id"
}

output "vpc_subnet_ids" {
  value       = data.aws_subnets.default.ids
  description = "default vpc subnet ids"
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
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.ssm_example_sg.id]
  associate_public_ip_address = true

  # startup config
  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true
}

output "ssm_instance_public_ip" {
  value       = aws_instance.ssm_example_instance.public_ip
  description = "public ip of ssm example instance"
}
