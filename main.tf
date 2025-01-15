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

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Use the archive_file data source to zip the Lambda code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/index.js"
  output_path = "${path.module}/function.zip"
}

resource "aws_lambda_function" "my_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "MyLambdaFunction"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# Enable Function URL for the Lambda
resource "aws_lambda_function_url" "my_lambda_url" {
  function_name      = aws_lambda_function.my_lambda.function_name
  authorization_type = "NONE" # Defines access control; "NONE" indicates no auth
}

output "lambda_function_url" {
  value = aws_lambda_function_url.my_lambda_url.function_url
}

resource "aws_cloudwatch_log_group" "my_log_group" {
  name              = "/aws/lambda/MyLambdaFunction"
  retention_in_days = 7
}

# --------------------------------------------------
# Data Protection

resource "aws_cloudwatch_log_group" "pii_detections" {
  name              = "pii-detections"
  retention_in_days = 0
}

locals {
  DataIdentifier = [
    "arn:aws:dataprotection::aws:data-identifier/Name",
    "arn:aws:dataprotection::aws:data-identifier/CreditCardExpiration",
    "arn:aws:dataprotection::aws:data-identifier/CreditCardNumber",
    "arn:aws:dataprotection::aws:data-identifier/CreditCardSecurityCode",
    "arn:aws:dataprotection::aws:data-identifier/Address",
    "AmalgamCompanyName"
  ]
}

resource "aws_cloudwatch_log_data_protection_policy" "my_log_group_protection" {
  log_group_name = aws_cloudwatch_log_group.my_log_group.name

  policy_document = jsonencode({
    Name    = "MyLogGroupDataProtection"
    Version = "2021-06-01"
    Configuration = {
      CustomDataIdentifier = [
        {
          Name  = "AmalgamCompanyName"
          Regex = "amalgam"
        }
      ]
    }
    Statement = [
      {
        Sid            = "For_Audit"
        DataIdentifier = local.DataIdentifier
        Operation = {
          Audit = {
            FindingsDestination = {
              CloudWatchLogs = {
                LogGroup = aws_cloudwatch_log_group.pii_detections.name
              }
            }
          }
        }
      },
      {
        Sid            = "For_Redact"
        DataIdentifier = local.DataIdentifier
        Operation = {
          Deidentify = {
            MaskConfig = {} #? no ref
          }
        }
      }
    ]
  })
}
