output "endpoint" {
  description = "Redis primary endpoint"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.main.port
}

output "cluster_id" {
  description = "Redis replication group ID"
  value       = aws_elasticache_replication_group.main.replication_group_id
}
