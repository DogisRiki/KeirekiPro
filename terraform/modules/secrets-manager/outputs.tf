output "rds_secret_arn" {
  description = "RDS secret ARN"
  value       = aws_secretsmanager_secret.rds.arn
}

output "rds_secret_id" {
  description = "RDS secret ID"
  value       = aws_secretsmanager_secret.rds.id
}

output "redis_secret_arn" {
  description = "Redis secret ARN"
  value       = aws_secretsmanager_secret.redis.arn
}

output "redis_secret_id" {
  description = "Redis secret ID"
  value       = aws_secretsmanager_secret.redis.id
}

output "jwt_secret_arn" {
  description = "JWT secret ARN"
  value       = aws_secretsmanager_secret.jwt.arn
}

output "google_oauth_secret_arn" {
  description = "Google OAuth secret ARN"
  value       = aws_secretsmanager_secret.google_oauth.arn
}

output "github_oauth_secret_arn" {
  description = "GitHub OAuth secret ARN"
  value       = aws_secretsmanager_secret.github_oauth.arn
}

output "alb_origin_verify_secret_arn" {
  description = "ALB Origin Verify secret ARN"
  value       = aws_secretsmanager_secret.alb_origin_verify.arn
}

output "alb_origin_verify_header_value" {
  description = "ALB Origin Verify header value"
  value       = random_password.alb_origin_verify.result
  sensitive   = true
}

output "rds_password" {
  description = "RDS password"
  value       = random_password.rds.result
  sensitive   = true
}

output "redis_password" {
  description = "Redis password"
  value       = random_password.redis.result
  sensitive   = true
}

output "all_secret_arns" {
  description = "List of all secret ARNs"
  value = [
    aws_secretsmanager_secret.rds.arn,
    aws_secretsmanager_secret.redis.arn,
    aws_secretsmanager_secret.jwt.arn,
    aws_secretsmanager_secret.google_oauth.arn,
    aws_secretsmanager_secret.github_oauth.arn,
    aws_secretsmanager_secret.alb_origin_verify.arn
  ]
}
