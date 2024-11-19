terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.76"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1" // N. Virginia
}

data "aws_vpc" "default" {
  default = true
}

output "default_vpc_id" {
  value = data.aws_vpc.default.id
}


# Get a subnet in the default VPC (in us-east-1a)
data "aws_subnet" "default" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "us-east-1a"
}

data "aws_key_pair" "generated_key" {
  key_name = "sample-instance-key"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"] # Owned by Amazon

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"] # Pattern for Amazon Linux 2 AMIs
  }
}

output "ami" {
  description = "amazon linux"
  value       = data.aws_ami.amazon_linux.id
}

resource "aws_security_group" "security-group-for-ssh" {
  name        = "security-group-for-ssh"
  vpc_id      = data.aws_vpc.default.id
  description = "Allow SSH traffic for all"
}

resource "aws_vpc_security_group_ingress_rule" "ingress-security-group-for-ssh" {
  security_group_id = aws_security_group.security-group-for-ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "egress-security-group-for-ssh" {
  security_group_id = aws_security_group.security-group-for-ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

resource "aws_instance" "sample_instance" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t4g.micro"
  subnet_id                   = data.aws_subnet.default.id
  vpc_security_group_ids      = [aws_security_group.security-group-for-ssh.id]
  associate_public_ip_address = true
  key_name                    = data.aws_key_pair.generated_key.key_name
  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }
  tags = {
    Name = "sample-instance"
  }
}

output "instance_public_ip" {
  value = aws_instance.sample_instance.public_ip
}

output "ssh_command" {
  value = "ssh -i private_key.pem ec2-user@${aws_instance.sample_instance.public_ip}"
}
