# IAM role for Lambda function
resource "aws_iam_role" "lambda_edge_role" {
  name = "lambda-edge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
        }
      }
    ]
  })
}

# IAM policy attachment for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_edge_role.name
}

# IAM policy for CloudWatch Logs
resource "aws_iam_role_policy" "lambda_edge_logs" {
  name = "lambda-edge-logs-policy"
  role = aws_iam_role.lambda_edge_role.id

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
      }
    ]
  })
}

# Lambda function for Hello World response
resource "aws_lambda_function" "hello_world" {
  filename      = "hello_world.zip"
  function_name = "hello-world-edge"
  role          = aws_iam_role.lambda_edge_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  publish       = true

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_edge_logs,
  ]
}

# Create the Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "hello_world.zip"
  source {
    content  = <<EOF
exports.handler = async (event) => {
    console.log('Lambda@Edge event:', JSON.stringify(event, null, 2));

    // Extract request details
    const request = event.Records[0].cf.request;
    const requestUrl = request.uri;
    const method = request.method;
    const headers = request.headers;

    console.log('Request URL: ' + requestUrl);
    console.log('Request Method: ' + method);
    console.log('Request Headers:', JSON.stringify(headers, null, 2));

    const response = {
        status: '200',
        statusDescription: 'OK',
        headers: {
            'content-type': [{
                key: 'Content-Type',
                value: 'text/html'
            }]
        },
        body: '<html><body>' +
              '<h1>Hello World from Lambda@Edge!</h1>' +
              '<p><strong>Request URL:</strong> ' + requestUrl + '</p>' +
              '<p><strong>Method:</strong> ' + method + '</p>' +
              '<p><strong>Timestamp:</strong> ' + new Date().toISOString() + '</p>' +
              '</body></html>'
    };

    console.log('Returning response:', JSON.stringify(response, null, 2));
    return response;
};
EOF
    filename = "index.js"
  }
}

# CloudFront Cache Policy
resource "aws_cloudfront_cache_policy" "lambda_cache_policy" {
  name        = "lambda-cache-policy"
  comment     = "Cache policy for Lambda@Edge responses"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

# CloudFront Origin Request Policy
resource "aws_cloudfront_origin_request_policy" "lambda_policy" {
  name    = "lambda-origin-request-policy"
  comment = "Policy for Lambda@Edge origin requests"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Host"]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "lambda_distribution" {

  origin {
    domain_name = "example.com"
    origin_id   = "lambda-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled = true

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "lambda-origin"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    cache_policy_id          = aws_cloudfront_cache_policy.lambda_cache_policy.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.lambda_policy.id

    lambda_function_association {
      event_type   = "origin-request"
      lambda_arn   = aws_lambda_function.hello_world.qualified_arn
      include_body = false
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Output the CloudFront distribution domain name
output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.lambda_distribution.domain_name
}

# Output the CloudFront distribution URL
output "cloudfront_url" {
  description = "The URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.lambda_distribution.domain_name}"
}
