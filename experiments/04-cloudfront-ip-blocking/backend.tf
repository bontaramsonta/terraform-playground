terraform {
  backend "s3" {
    bucket  = "my-tf-state-3y5"
    key     = "terraform/play/04-cloudfront-ip-blocking.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}
