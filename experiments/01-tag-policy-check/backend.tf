terraform {
  backend "s3" {
    bucket  = "my-tf-state-3y5"
    key     = "terraform/play/01-tag-policy-check.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}
