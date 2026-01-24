output "endpoint" {
  description = "RDS endpoint (without port)"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS port"
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "username" {
  description = "Database username"
  value       = aws_db_instance.main.username
}

output "instance_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}
