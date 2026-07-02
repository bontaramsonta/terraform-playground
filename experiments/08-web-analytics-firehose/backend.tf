terraform {
  backend "s3" {
    bucket  = "my-tf-state-3y5"
    key     = "terraform/play/08-web-analytics-firehose.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}
