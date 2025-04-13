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
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "${var.region}a"
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
  subnet_id              = aws_subnet.my_private_subnet.id
  vpc_security_group_ids = [aws_security_group.ssm_example_sg.id]
}

resource "aws_security_group" "ssm_endpoint_sg" {
  name   = "ssm-endpoint-sg"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    description = "Allow HTTPS traffic from EC2 instances in the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.my_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.my_vpc.id
  subnet_ids          = [aws_subnet.my_private_subnet.id]
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  private_dns_enabled = true
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ssm_endpoint_sg.id]
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.my_vpc.id
  subnet_ids          = [aws_subnet.my_private_subnet.id]
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  private_dns_enabled = true
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ssm_endpoint_sg.id]
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.my_vpc.id
  subnet_ids          = [aws_subnet.my_private_subnet.id]
  service_name        = "com.amazonaws.${var.region}.ssm"
  private_dns_enabled = true
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ssm_endpoint_sg.id]
}

resource "aws_security_group" "ssm_example_sg" {
  name   = "ssm-example-sg"
  vpc_id = aws_vpc.my_vpc.id

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

resource "aws_ec2_instance_connect_endpoint" "my_endpoint" {
  subnet_id = aws_subnet.my_private_subnet.id
}
