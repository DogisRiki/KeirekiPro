resource "aws_elasticache_user" "app" {
  engine = "valkey"
}

resource "aws_elasticache_serverless_cache" "main" {
  engine               = "valkey"
  major_engine_version = "8"
}
