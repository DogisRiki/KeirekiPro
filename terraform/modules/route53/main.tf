# A Record (Alias) for CloudFront
resource "aws_route53_record" "app_a" {
  zone_id = var.zone_id
  name    = var.app_domain_name
  type    = "A"

  alias {
    name                   = var.cloudfront_distribution_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# AAAA Record (Alias) for CloudFront (IPv6)
resource "aws_route53_record" "app_aaaa" {
  zone_id = var.zone_id
  name    = var.app_domain_name
  type    = "AAAA"

  alias {
    name                   = var.cloudfront_distribution_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# A Record (Alias) for ALB API subdomain
resource "aws_route53_record" "api_a" {
  zone_id = var.zone_id
  name    = var.api_domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
