variable "zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}

variable "app_domain_name" {
  description = "Application domain name"
  type        = string
}

variable "cloudfront_distribution_domain_name" {
  description = "CloudFront distribution domain name"
  type        = string
}

variable "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID (fixed value: Z2FDTNDATAQYW2)"
  type        = string
}
