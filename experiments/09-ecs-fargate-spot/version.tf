terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.21.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.7.1"
    }
  }

  backend "s3" {
    bucket  = "my-tf-state-3y5"
    key     = "terraform/play/09-ecs-fargate-spot.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}

provider "aws" {
  region  = "ap-south-1"
  profile = "sourav"
}
