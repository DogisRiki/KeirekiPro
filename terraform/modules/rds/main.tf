# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Subnet group for KeirekiPro RDS"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  name        = "${var.project_name}-db-params"
  family      = "postgres17"
  description = "Parameter group for KeirekiPro RDS"

  parameter {
    name  = "timezone"
    value = "Asia/Tokyo"
  }

  parameter {
    name  = "log_timezone"
    value = "Asia/Tokyo"
  }

  parameter {
    name  = "log_statement"
    value = "none"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name = "${var.project_name}-db-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-db"

  # Engine
  engine         = "postgres"
  engine_version = "17.4"

  # Instance
  instance_class         = "db.t4g.micro"
  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  port                   = 5432

  # Storage
  storage_type          = "gp3"
  allocated_storage     = 20
  max_allocated_storage = 20
  storage_encrypted     = true

  # Database
  db_name  = "keireki_pro"
  username = "keirekipro_master"
  password = var.db_password

  # Parameter group
  parameter_group_name = aws_db_parameter_group.main.name

  # Backup
  backup_retention_period   = 7
  backup_window             = "18:00-19:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-db-final-snapshot"

  # Maintenance
  auto_minor_version_upgrade = true
  maintenance_window         = "Sun:19:00-Sun:20:00"

  # Monitoring
  enabled_cloudwatch_logs_exports = []
  performance_insights_enabled    = false

  # Protection
  deletion_protection = true

  tags = {
    Name = "${var.project_name}-db"
  }
}
