terraform {
  backend "s3" {
    bucket  = "my-tf-state-3y5"
    key     = "terraform/play/03-guardduty-ecs-runtime-monitoring.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}
