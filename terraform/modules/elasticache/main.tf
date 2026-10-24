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
