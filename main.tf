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

locals {
  bucket-name = "<origin_bucket_name>"
  allowed_ips = [
    "<example_ip>"
  ]
}

# cf stuffs
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "s3-oac"
  description                       = "OAC for S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ! ./function.js
resource "aws_cloudfront_function" "test" {
  name    = "ip-based-whitelisting"
  runtime = "cloudfront-js-2.0"
  comment = "this function allows only certain ips"
  publish = true
  code    = templatefile("${path.module}/function.js", { allowed_ips = join(",", local.allowed_ips) })
}

output "function_code" {
  value = aws_cloudfront_function.test.code
}

resource "aws_cloudfront_distribution" "cf-dist" {
  enabled             = true
  default_root_object = "index.html"
  origin {
    domain_name              = aws_s3_bucket.builds-bucket.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.builds-bucket.id
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.builds-bucket.id
    viewer_protocol_policy = "allow-all"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }
  ordered_cache_behavior {
    path_pattern           = "/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.builds-bucket.id
    viewer_protocol_policy = "allow-all"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.test.arn
    }
  }
}

# bucket stuff

resource "aws_s3_bucket" "builds-bucket" {
  bucket = local.bucket-name
}

resource "aws_s3_object" "html-file" {
  bucket       = aws_s3_bucket.builds-bucket.bucket
  key          = "index.html"
  source       = "./index.html"
  content_type = "text/html"
  etag         = filemd5("./index.html")
}

resource "aws_s3_bucket_public_access_block" "builds-bucket-public_access" {
  bucket = aws_s3_bucket.builds-bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "builds-bucket-policy" {
  bucket = aws_s3_bucket.builds-bucket.id
  policy = data.aws_iam_policy_document.allow_access_s3_oac_access.json
}

# bucket policy allowing access to cloudfront distribution
data "aws_iam_policy_document" "allow_access_s3_oac_access" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.builds-bucket.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cf-dist.arn]
    }
  }
}

output "cf-alias" {
  value = aws_cloudfront_distribution.cf-dist.domain_name
}
