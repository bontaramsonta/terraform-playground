data "aws_caller_identity" "current" {}

# S3 bucket for storing analytics data
resource "aws_s3_bucket" "analytics_data" {
  bucket = "web-analytics-data-${random_string.bucket_suffix.result}"
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "analytics_data_versioning" {
  bucket = aws_s3_bucket.analytics_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "analytics_data_encryption" {
  bucket = aws_s3_bucket.analytics_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "analytics-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda to access S3 and CloudWatch logs
resource "aws_iam_role_policy" "lambda_policy" {
  name = "analytics-lambda-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "${aws_s3_bucket.analytics_data.arn}/*"
      },
    ]
  })
}

# Hash of the Lambda source code to trigger redeployment when code changes
locals {
  lambda_source_hash = filebase64sha256("${path.module}/lambda/index.js")
}

# Create the lambda function zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/analytics_processor.zip"


  source_dir = "${path.module}/lambda"
}

# Lambda function to process analytics data
resource "aws_lambda_function" "analytics_processor" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "analytics-data-processor"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 60

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_log_group
  ]
}

# IAM role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_delivery_role" {
  name = "analytics-firehose-delivery-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Firehose to access S3 and Lambda
resource "aws_iam_role_policy" "firehose_policy" {
  name = "analytics-firehose-policy"
  role = aws_iam_role.firehose_delivery_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.analytics_data.arn,
          "${aws_s3_bucket.analytics_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.analytics_processor.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Kinesis Data Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "analytics_stream" {
  name        = "analytics-data-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn       = aws_iam_role.firehose_delivery_role.arn
    bucket_arn     = aws_s3_bucket.analytics_data.arn
    file_extension = ".csv"

    buffering_size     = 5
    buffering_interval = 60

    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.analytics_processor.arn
        }
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/kinesisfirehose/analytics-data-stream"
      log_stream_name = "WebAnalyticsS3Delivery"
    }
  }
}

# CloudWatch Log Group for Firehose
resource "aws_cloudwatch_log_group" "firehose_log_group" {
  name              = "/aws/kinesisfirehose/analytics-data-stream"
  retention_in_days = 14
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/analytics-data-processor"
  retention_in_days = 14
}

# Cognito Identity Pool for web analytics
resource "aws_cognito_identity_pool" "analytics_identity_pool" {
  identity_pool_name               = "web_analytics_identity_pool"
  allow_unauthenticated_identities = true
  allow_classic_flow               = false

  tags = {
    Name        = "Web Analytics Identity Pool"
    Environment = "development"
  }
}

# IAM role for unauthenticated users
resource "aws_iam_role" "cognito_unauthenticated_role" {
  name = "analytics-cognito-unauthenticated-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.analytics_identity_pool.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "unauthenticated"
          }
        }
      }
    ]
  })
}

# IAM role for authenticated users
resource "aws_iam_role" "cognito_authenticated_role" {
  name = "analytics-cognito-authenticated-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.analytics_identity_pool.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })
}

# IAM policy for unauthenticated users to put records in Firehose
resource "aws_iam_role_policy" "cognito_unauthenticated_policy" {
  name = "analytics-cognito-unauthenticated-policy"
  role = aws_iam_role.cognito_unauthenticated_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.analytics_stream.arn
      }
    ]
  })
}

# IAM policy for authenticated users to put records in Firehose
resource "aws_iam_role_policy" "cognito_authenticated_policy" {
  name = "analytics-cognito-authenticated-policy"
  role = aws_iam_role.cognito_authenticated_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.analytics_stream.arn
      }
    ]
  })
}

# Attach roles to Cognito Identity Pool
resource "aws_cognito_identity_pool_roles_attachment" "analytics_identity_pool_roles" {
  identity_pool_id = aws_cognito_identity_pool.analytics_identity_pool.id

  roles = {
    authenticated   = aws_iam_role.cognito_authenticated_role.arn
    unauthenticated = aws_iam_role.cognito_unauthenticated_role.arn
  }
}

# Outputs
output "current_user_id" {
  value = data.aws_caller_identity.current.user_id
}

output "firehose_stream_name" {
  value       = aws_kinesis_firehose_delivery_stream.analytics_stream.name
  description = "Name of the Kinesis Data Firehose stream for analytics ingestion"
}

output "firehose_stream_arn" {
  value       = aws_kinesis_firehose_delivery_stream.analytics_stream.arn
  description = "ARN of the Kinesis Data Firehose stream"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.analytics_data.bucket
  description = "Name of the S3 bucket storing analytics data"
}

output "lambda_function_name" {
  value       = aws_lambda_function.analytics_processor.function_name
  description = "Name of the Lambda function processing analytics data"
}

output "cognito_identity_pool_id" {
  value       = aws_cognito_identity_pool.analytics_identity_pool.id
  description = "ID of the Cognito Identity Pool for web analytics"
}

output "cognito_unauthenticated_role_arn" {
  value       = aws_iam_role.cognito_unauthenticated_role.arn
  description = "ARN of the unauthenticated role for Cognito Identity Pool"
}

output "cognito_authenticated_role_arn" {
  value       = aws_iam_role.cognito_authenticated_role.arn
  description = "ARN of the authenticated role for Cognito Identity Pool"
}
