output "cloudfront_certificate_arn" {
  description = "CloudFront ACM certificate ARN (us-east-1)"
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}

output "alb_certificate_arn" {
  description = "ALB ACM certificate ARN (ap-northeast-1)"
  value       = aws_acm_certificate_validation.alb.certificate_arn
}

output "alb_api_certificate_arn" {
  description = "ALB API ACM certificate ARN (ap-northeast-1)"
  value       = aws_acm_certificate_validation.alb_api.certificate_arn
}
