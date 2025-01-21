terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-south-1"
}

resource "aws_guardduty_detector" "guard_duty_enable" {
  enable = true
}

locals {
  guardduty_detector_features = [
    "EKS_AUDIT_LOGS",
    "EBS_MALWARE_PROTECTION",
    "RDS_LOGIN_EVENTS",
    "LAMBDA_NETWORK_LOGS",
    "S3_DATA_EVENTS",
    "RUNTIME_MONITORING"
  ]
}

resource "aws_guardduty_detector_feature" "guardduty_detector_feature" {
  count       = length(local.guardduty_detector_features)
  detector_id = aws_guardduty_detector.guard_duty_enable.id
  name        = local.guardduty_detector_features[count.index]
  status      = "ENABLED"

  dynamic "additional_configuration" {
    for_each = local.guardduty_detector_features[count.index] == "RUNTIME_MONITORING" ? [1] : []
    content {
      name   = "EKS_ADDON_MANAGEMENT"
      status = "DISABLED"
    }
  }

  dynamic "additional_configuration" {
    for_each = local.guardduty_detector_features[count.index] == "RUNTIME_MONITORING" ? [1] : []
    content {
      name   = "ECS_FARGATE_AGENT_MANAGEMENT"
      status = "ENABLED"
    }
  }

  dynamic "additional_configuration" {
    for_each = local.guardduty_detector_features[count.index] == "RUNTIME_MONITORING" ? [1] : []
    content {
      name   = "EC2_AGENT_MANAGEMENT"
      status = "DISABLED"
    }
  }
}
