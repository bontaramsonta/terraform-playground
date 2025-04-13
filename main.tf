variable "region" {
  description = "The AWS region where resources will be created"
  default     = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.94.1"
    }
  }
  backend "s3" {
    bucket       = "my-tf-state-3y5"
    key          = "terraform/default-state"
    region       = "ap-south-1"
    use_lockfile = true
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "managed_by" = "terraform",
      "region"     = var.region,
      "project"    = "ssm-example-public"
    }
  }
}

resource "aws_default_vpc" "default" {}

resource "aws_default_subnet" "default_subnet" {
  availability_zone = "${var.region}a"
}

output "default_vpc_id" {
  value       = aws_default_vpc.default.id
  description = "The ID of the default VPC"
}

output "default_subnet_id" {
  value       = aws_default_subnet.default_subnet.id
  description = "The ID of the default subnet"
}

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
    values = ["x86_64"]
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

output "ami-id" {
  value       = data.aws_ami.amazon_linux_2.id
  description = "ami id of latest amazon linux 2 in ap-south-1"
}

# IAM stuff
resource "aws_iam_role" "ssm_role" {
  name = "SSM-Session-Manager-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ssm_role.name
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "SSM-Instance-Profile"
  role = aws_iam_role.ssm_role.name
}

# Instance
resource "aws_instance" "ssm_example_instance" {
  ami                  = data.aws_ami.amazon_linux_2.id
  instance_type        = "t2.micro"
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  # For IMDv2
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # network config
  subnet_id              = aws_default_subnet.default_subnet.id
  vpc_security_group_ids = [aws_security_group.ssm_example_sg.id]
}

resource "aws_security_group" "ssm_example_sg" {
  name   = "ssm-example-sg"
  vpc_id = aws_default_vpc.default.id

  ingress {
    description      = "Inbound SSH traffic from EC2 Instance Connect Endpoint"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
