terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.94.1"
    }
  }
  backend "s3" {
    bucket       = "my-tf-state-3y5"
    key          = "terraform/play/07-cloudfront-lambda-edge.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
  }
}

variable "region" {
  description = "The AWS region where resources will be created"
  default     = "us-east-1"
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "managed_by" = "terraform",
      "region"     = var.region,
      "project"    = "tf-play"
    }
  }
}
