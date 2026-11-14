# Origin Access Control for Frontend S3
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-frontend-oac"
  description                       = "OAC for frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Origin Access Control for Storage S3
resource "aws_cloudfront_origin_access_control" "storage" {
  name                              = "${var.project_name}-storage-oac"
  description                       = "OAC for storage S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# VPC Origin for internal ALB
resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "${var.project_name}-alb-vpc-origin"
    arn                    = var.alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = {
    Name = "${var.project_name}-alb-vpc-origin"
  }
}

# SPA の画面の URL を /index.html に書き換える関数
resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${var.project_name}-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite SPA routes to /index.html"
  publish = true
  code    = file("${path.module}/spa-rewrite.js")
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  comment             = "KeirekiPro CDN Distribution"
  default_root_object = "index.html"
  price_class         = "PriceClass_200"
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  web_acl_id          = var.waf_web_acl_arn

  aliases = [var.app_domain_name]

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # S3 Frontend Origin
  origin {
    domain_name              = var.frontend_bucket_regional_domain_name
    origin_id                = "S3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # S3 Storage Origin
  origin {
    domain_name              = var.storage_bucket_regional_domain_name
    origin_id                = "S3-storage"
    origin_access_control_id = aws_cloudfront_origin_access_control.storage.id
  }

  # ALB API Origin
  origin {
    domain_name = var.api_domain_name
    origin_id   = "ALB-api"

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.alb.id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_verify_header_value
    }
  }

  # Default behavior (S3 Frontend)
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03" # SecurityHeadersPolicy

    # 画面の URL を /index.html に書き換える(SPA のルーティング)。
    # custom_error_response はディストリビューション全体に効き、/api/* の 403 と 404 まで
    # /index.html に置き換えてしまうため、既定の経路だけで書き換える。
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  # API behavior
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-api"
    viewer_protocol_policy = "https-only"
    compress               = false

    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader
  }

  # Media behavior
  ordered_cache_behavior {
    path_pattern           = "/media/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-storage"
    viewer_protocol_policy = "https-only"
    compress               = true

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${var.project_name}-distribution"
  }
}
