#S3 Bucket
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.name_prefix}-frontend"
  force_destroy = true

  tags = {
    Name = "${var.name_prefix}-frontend"
  }
}

#Enabling S3 versioning
resource "aws_s3_bucket_versioning" "my_bucket_versioning" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}


#Blocking all public access Only cloudfront is allowed
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}




# S3 BUCKET POLICY
# Only CloudFront (this specific distribution) can read from this bucket.
# AWS:SourceArn condition locks it to our distribution — not just any CloudFront.
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}


# ORIGIN ACCESS CONTROL (OAC)
# The mechanism that allows CloudFront to read from private S3.
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.name_prefix}-oac"
  description                       = "OAC for ${var.name_prefix} frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}





# CLOUDFRONT DISTRIBUTION
# CDN that serves your frontend globally.
# Two origins:
#   1. S3 — serves HTML/CSS/JS (default)
#   2. ALB — forwards /api/* requests to Flask
resource "aws_cloudfront_distribution" "main" {

  # --- Origin 1: S3 (static website) ---
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "myS3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # --- Origin 2: ALB (Flask app) ---
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "myALBOrigin" # this name can be anything 

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # or "https-only" if ALB has SSL
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # --- Default Cache Behavior: S3 (serves / by default) ---
  default_cache_behavior {
    target_origin_id       = "myS3Origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
    compress    = true
  }

  # --- Ordered Cache Behavior: ALB (handles /api/*) ---
  ordered_cache_behavior {
    path_pattern           = "/api/*"      # ← any request to /api/ goes to ALB
    target_origin_id       = "myALBOrigin" # should match the origin_id name thats all
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = true                                  # forward query strings to Flask
      headers      = ["Authorization", "Origin", "Accept"] # forward these headers
      cookies {
        forward = "all" # forward cookies to Flask
      }
    }

    min_ttl     = 0
    default_ttl = 0 # don't cache API responses
    max_ttl     = 0 # don't cache API responses
    compress    = true
  }

  # --- Custom Error for SPA routing ---
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # ATTACHING THE WAF TO CLOUDFRONT
  web_acl_id = aws_wafv2_web_acl.main.arn

  depends_on = [aws_s3_bucket_public_access_block.frontend]

  tags = {
    Name = "${var.name_prefix}-cloudfront"
  }
}



# CREATING WAF 

resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1

  name        = "${var.name_prefix}-waf"
  description = "WAF for my app"
  scope       = "CLOUDFRONT" # "REGIONAL" for ALB, "CLOUDFRONT" for CloudFront

  # --- Default action if no rules match ---
  default_action {
    allow {} # allow by default, rules will block specific things
    # block {}  # block by default, rules will allow specific things
  }

  # --- Rule 1: AWS Managed Common Rule Set ---
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {} # use the rule's own action
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # --- Rule 2: AWS Managed SQL Injection Rule ---
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesSQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # --- Rule 3: Rate limiting (block if > 100 req/5min from same IP) ---
  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100 # max requests per 5 minutes
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # --- Required on every WAF ---
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.name_prefix}-waf"
  }
}