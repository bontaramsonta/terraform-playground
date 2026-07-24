terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# AWS End User Messaging SMS *origination* simulator numbers are US-only
# (docs.aws.amazon.com/sms-voice/latest/userguide/test-phone-numbers.html),
# so this experiment must run in a US region regardless of the play default
# (ap-south-1). us-east-1 also matches where Avhana actually sends.
provider "aws" {
  region = "us-east-1"
}

# ---------------------------------------------------------------------------
# The nine v2 failure event types + filter pattern — copied VERBATIM from
# ticket 04's resolution so this experiment tests the *real* production filter,
# not a paraphrase. If 04 changes, this must change with it.
#   .scratch/sms-failure-alarm/issues/04-terraform-module-design.md (decision 8)
locals {
  sms_failure_event_types = [
    "TEXT_BLOCKED", "TEXT_CARRIER_BLOCKED", "TEXT_CARRIER_UNREACHABLE",
    "TEXT_INVALID", "TEXT_INVALID_MESSAGE", "TEXT_PROTECT_BLOCKED",
    "TEXT_SPAM", "TEXT_TTL_EXPIRED", "TEXT_UNREACHABLE",
  ]
  sms_failure_filter_pattern = "{ ${join(" || ", [for t in local.sms_failure_event_types : "$.eventType = \"${t}\""])} }"

  # US destination "magic" simulator numbers — one success, one failure per
  # country (test-phone-numbers.html). There is only ONE failure number and its
  # emitted TEXT_* subtype is UNDOCUMENTED, which is exactly why the event
  # destination below matches TEXT_ALL: capture whatever it actually emits.
  sim_success_destination = "+14254147755"
  sim_failure_destination = "+14254147167"
}

# ---------------------------------------------------------------------------
# Throwaway log group the v2 event destination writes into.
resource "aws_cloudwatch_log_group" "sms_events" {
  name              = "play/sms-v2-serialization/events"
  retention_in_days = 1
}

# IAM role the SMS v2 event destination assumes to write to CloudWatch Logs.
# Trust + permissions mirror the production sms-settings-module, INCLUDING the
# logs:DescribeLogStreams that ticket 02 found missing there (main.tf:33).
resource "aws_iam_role" "sms_events_to_cw" {
  name = "play-sms-v2-events-to-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "sms-voice.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sms_events_to_cw" {
  name = "write-sms-events"
  role = aws_iam_role.sms_events_to_cw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
      ]
      Resource = [
        aws_cloudwatch_log_group.sms_events.arn,
        "${aws_cloudwatch_log_group.sms_events.arn}:*",
      ]
    }]
  })
}

# ---------------------------------------------------------------------------
# Config set + event destination. matching_event_types = TEXT_ALL so we log
# whatever the (undocumented-subtype) failure number emits, and can eyeball the
# raw serialization. log_group_arn takes an ARN despite AWS prose (ticket 02/Q9).
resource "aws_pinpointsmsvoicev2_configuration_set" "exp" {
  name = "play-sms-v2-serialization"
}

resource "aws_pinpointsmsvoicev2_event_destination" "cw" {
  configuration_set_name = aws_pinpointsmsvoicev2_configuration_set.exp.name
  event_destination_name = "sms-events-to-cloudwatch"
  matching_event_types   = ["TEXT_ALL"]

  cloudwatch_logs_destination {
    iam_role_arn  = aws_iam_role.sms_events_to_cw.arn
    log_group_arn = aws_cloudwatch_log_group.sms_events.arn
  }
}

# US simulator origination number — "does not require registration"
# (getting-started-tutorial.html). Leased on request; SMS-only is enough.
resource "aws_pinpointsmsvoicev2_phone_number" "simulator" {
  iso_country_code            = "US"
  message_type                = "TRANSACTIONAL"
  number_type                 = "SIMULATOR"
  number_capabilities         = ["SMS"]
  deletion_protection_enabled = false
}

# ---------------------------------------------------------------------------
# The PRODUCTION ticket-04 JSON filter, verbatim, on this log group emitting a
# canary metric. This is the payoff: if it increments on a real failure line,
# the $.eventType path lands and the whitespace-insensitivity claim holds.
resource "aws_cloudwatch_log_metric_filter" "v2_json_canary" {
  name           = "SMS_Failure_JsonCanary"
  log_group_name = aws_cloudwatch_log_group.sms_events.name
  pattern        = local.sms_failure_filter_pattern

  metric_transformation {
    name      = "SMS_Failure_JsonCanary"
    namespace = "LogMetrics"
    value     = "1"
  }
}

# ---------------------------------------------------------------------------
output "log_group_name" {
  value = aws_cloudwatch_log_group.sms_events.name
}

output "configuration_set_name" {
  value = aws_pinpointsmsvoicev2_configuration_set.exp.name
}

output "origination_number_id" {
  value = aws_pinpointsmsvoicev2_phone_number.simulator.id
}

output "sim_success_destination" {
  value = local.sim_success_destination
}

output "sim_failure_destination" {
  value = local.sim_failure_destination
}

output "json_canary_filter_pattern" {
  value = local.sms_failure_filter_pattern
}
