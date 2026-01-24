variable "project_name" {
  description = "Project name"
  type        = string
}

variable "app_domain_name" {
  description = "Application domain name"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN (us-east-1)"
  type        = string
}

variable "frontend_bucket_regional_domain_name" {
  description = "Frontend S3 bucket regional domain name"
  type        = string
}

variable "storage_bucket_regional_domain_name" {
  description = "Storage S3 bucket regional domain name"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name"
  type        = string
}

variable "origin_verify_header_value" {
  description = "X-Origin-Verify header value"
  type        = string
  sensitive   = true
}

variable "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  type        = string
}
