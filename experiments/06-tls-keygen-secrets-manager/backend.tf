terraform {
  backend "s3" {
    bucket  = "my-tf-state-3y5"
    key     = "terraform/play/06-tls-keygen-secrets-manager.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}
