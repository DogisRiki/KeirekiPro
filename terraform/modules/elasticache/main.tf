# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-redis-subnet-group"
  description = "Subnet group for KeirekiPro Redis"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-redis-subnet-group"
  }
}

# ElastiCache Parameter Group
resource "aws_elasticache_parameter_group" "main" {
  name        = "${var.project_name}-redis-params"
  family      = "valkey8"
  description = "Parameter group for KeirekiPro Redis"

  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  tags = {
    Name = "${var.project_name}-redis-params"
  }
}

# ElastiCache Replication Group (Valkey) - Single node with AUTH support
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.project_name}-redis"
  description          = "KeirekiPro Redis cache"

  engine               = "valkey"
  engine_version       = "8.0"
  node_type            = "cache.t4g.micro"
  num_cache_clusters   = 1
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [var.security_group_id]

  # Authentication
  transit_encryption_enabled = true
  auth_token                 = var.auth_token

  # Maintenance
  maintenance_window         = "sun:20:00-sun:21:00"
  auto_minor_version_upgrade = true

  # Backup
  snapshot_retention_limit = 0

  # Multi-AZ disabled for cost optimization
  automatic_failover_enabled = false
  multi_az_enabled           = false

  tags = {
    Name = "${var.project_name}-redis"
  }
}

# ElastiCache RBAC User for the application
resource "aws_elasticache_user" "app" {
  user_id       = "${var.project_name}-app"
  user_name     = "${var.project_name}-app"
  engine        = "valkey"
  access_string = "on ~* &* +@all"

  authentication_mode {
    type      = "password"
    passwords = [var.app_user_password]
  }

  tags = {
    Name = "${var.project_name}-app"
  }
}

# ElastiCache RBAC User Group (Valkey does not require the default user)
resource "aws_elasticache_user_group" "app" {
  user_group_id = "${var.project_name}-app"
  engine        = "valkey"
  user_ids      = [aws_elasticache_user.app.user_id]

  tags = {
    Name = "${var.project_name}-app"
  }
}

# ElastiCache Serverless (Valkey)
resource "aws_elasticache_serverless_cache" "main" {
  name                 = "${var.project_name}-cache"
  engine               = "valkey"
  major_engine_version = "8"
  subnet_ids           = var.private_subnet_ids
  security_group_ids   = [var.security_group_id]
  user_group_id        = aws_elasticache_user_group.app.user_group_id

  cache_usage_limits {
    data_storage {
      maximum = 1
      unit    = "GB"
    }

    ecpu_per_second {
      maximum = 1000
    }
  }

  tags = {
    Name = "${var.project_name}-cache"
  }
}
