# Random password for RDS
resource "random_password" "rds" {
  length  = 32
  special = false
}

# Random password for Redis
resource "random_password" "redis" {
  length  = 32
  special = false
}

# Random value for ALB Origin Verify header
resource "random_password" "alb_origin_verify" {
  length  = 64
  special = false
}

# RDS Secret
resource "aws_secretsmanager_secret" "rds" {
  name                    = "${var.project_name}/rds"
  description             = "RDS database connection information"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}/rds"
  }
}

# Redis Secret
resource "aws_secretsmanager_secret" "redis" {
  name                    = "${var.project_name}/redis"
  description             = "ElastiCache Redis connection information"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}/redis"
  }
}

# JWT Secret
resource "aws_secretsmanager_secret" "jwt" {
  name                    = "${var.project_name}/jwt"
  description             = "JWT signing key"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}/jwt"
  }
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({
    "jwt-secret" = var.jwt_secret
  })
}

# Google OAuth Secret
resource "aws_secretsmanager_secret" "google_oauth" {
  name                    = "${var.project_name}/oidc/google"
  description             = "Google OAuth client credentials"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}/oidc/google"
  }
}

resource "aws_secretsmanager_secret_version" "google_oauth" {
  secret_id = aws_secretsmanager_secret.google_oauth.id
  secret_string = jsonencode({
    client_id     = var.google_oauth_client_id
    client_secret = var.google_oauth_client_secret
  })
}

# GitHub OAuth Secret
resource "aws_secretsmanager_secret" "github_oauth" {
  name                    = "${var.project_name}/oidc/github"
  description             = "GitHub OAuth client credentials"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}/oidc/github"
  }
}

resource "aws_secretsmanager_secret_version" "github_oauth" {
  secret_id = aws_secretsmanager_secret.github_oauth.id
  secret_string = jsonencode({
    client_id     = var.github_oauth_client_id
    client_secret = var.github_oauth_client_secret
  })
}

# ALB Origin Verify Secret
resource "aws_secretsmanager_secret" "alb_origin_verify" {
  name                    = "${var.project_name}/alb-origin-verify"
  description             = "ALB direct access prevention header value"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}/alb-origin-verify"
  }
}

resource "aws_secretsmanager_secret_version" "alb_origin_verify" {
  secret_id = aws_secretsmanager_secret.alb_origin_verify.id
  secret_string = jsonencode({
    headerValue = random_password.alb_origin_verify.result
  })
}
