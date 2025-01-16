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
  enabled_features_for_runtime_monitoring = {
    EKS_ADDON_MANAGEMENT         = "DISABLED"
    ECS_FARGATE_AGENT_MANAGEMENT = "ENABLED"
    EC2_AGENT_MANAGEMENT         = "DISABLED"
  }
}

resource "aws_guardduty_detector_feature" "guardduty_detector_feature" {
  count       = length(local.guardduty_detector_features)
  detector_id = aws_guardduty_detector.guard_duty_enable.id
  name        = local.guardduty_detector_features[count.index]
  status      = "ENABLED"

  dynamic "additional_configuration" {
    for_each = local.guardduty_detector_features[count.index] == "RUNTIME_MONITORING" ? local.enabled_features_for_runtime_monitoring : {}
    content {
      name   = additional_configuration.key
      status = additional_configuration.value
    }
  }

  lifecycle {
    ignore_changes = [
      additional_configuration[0].name,
      additional_configuration[1].name,
      additional_configuration[2].name
    ]
  }
}
