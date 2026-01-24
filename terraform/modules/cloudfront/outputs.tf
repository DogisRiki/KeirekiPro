output "distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "distribution_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "frontend_oac_id" {
  description = "Frontend OAC ID"
  value       = aws_cloudfront_origin_access_control.frontend.id
}

output "storage_oac_id" {
  description = "Storage OAC ID"
  value       = aws_cloudfront_origin_access_control.storage.id
}
