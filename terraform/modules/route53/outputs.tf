output "app_record_name" {
  description = "Application A record name"
  value       = aws_route53_record.app_a.name
}
