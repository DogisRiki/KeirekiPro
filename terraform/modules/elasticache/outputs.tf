output "endpoint" {
  description = "ElastiCache Serverless endpoint address"
  value       = aws_elasticache_serverless_cache.main.endpoint[0].address
}

output "port" {
  description = "ElastiCache Serverless endpoint port"
  value       = aws_elasticache_serverless_cache.main.endpoint[0].port
}

output "cluster_id" {
  description = "ElastiCache Serverless cache name"
  value       = aws_elasticache_serverless_cache.main.name
}

output "username" {
  description = "RBAC user name for the application"
  value       = aws_elasticache_user.app.user_name
}
