terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.94.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
  }
  backend "s3" {
    bucket       = "my-tf-state-3y5"
    key          = "terraform/default-state"
    region       = "ap-south-1"
    use_lockfile = true
  }
}

# RSA key of size 4096 bits
resource "tls_private_key" "rsa-4096-example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

output "private_key" {
  value = nonsensitive(tls_private_key.rsa-4096-example.private_key_pem)
}

output "public_key" {
  value = nonsensitive(tls_private_key.rsa-4096-example.private_key_pem)
}
