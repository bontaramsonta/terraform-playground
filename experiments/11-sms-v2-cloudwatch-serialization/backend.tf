terraform {
  backend "s3" {
    bucket  = "my-tf-state-3y5"
    key     = "terraform/play/11-sms-v2-cloudwatch-serialization.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}
