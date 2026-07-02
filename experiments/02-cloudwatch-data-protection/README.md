# CloudWatch Logs data protection (PII redaction)

Tests `aws_cloudwatch_log_data_protection_policy`: a Lambda (with function
URL) writes log lines containing fake PII; the data protection policy on its
log group detects and redacts it, with detections audited to a second log
group (`pii_detections`). `caller.js` drives test traffic.
