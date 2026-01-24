output "frontend_bucket_name" {
  description = "Frontend bucket name"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "Frontend bucket ARN"
  value       = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_regional_domain_name" {
  description = "Frontend bucket regional domain name"
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
}

output "storage_bucket_name" {
  description = "Storage bucket name"
  value       = aws_s3_bucket.storage.id
}

output "storage_bucket_arn" {
  description = "Storage bucket ARN"
  value       = aws_s3_bucket.storage.arn
}

output "storage_bucket_regional_domain_name" {
  description = "Storage bucket regional domain name"
  value       = aws_s3_bucket.storage.bucket_regional_domain_name
}

output "alb_logs_bucket_name" {
  description = "ALB logs bucket name"
  value       = aws_s3_bucket.alb_logs.id
}
