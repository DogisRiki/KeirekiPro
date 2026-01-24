# Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Provider for us-east-1 (CloudFront ACM certificate)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

# Data source for AWS account ID
data "aws_caller_identity" "current" {}

# Data source for Route 53 hosted zone (created manually)
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  availability_zones   = ["ap-northeast-1a", "ap-northeast-1c"]
}

# S3 Module (created early, bucket policies applied after CloudFront)
module "s3" {
  source = "./modules/s3"

  project_name   = var.project_name
  aws_account_id = data.aws_caller_identity.current.account_id
}

# Secrets Manager Module
module "secrets_manager" {
  source = "./modules/secrets-manager"

  project_name               = var.project_name
  jwt_secret                 = var.jwt_secret
  google_oauth_client_id     = var.google_oauth_client_id
  google_oauth_client_secret = var.google_oauth_client_secret
  github_oauth_client_id     = var.github_oauth_client_id
  github_oauth_client_secret = var.github_oauth_client_secret
}

# RDS Module
module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.vpc.rds_security_group_id
  db_password        = module.secrets_manager.rds_password
}

# ElastiCache Module
module "elasticache" {
  source = "./modules/elasticache"

  project_name       = var.project_name
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.vpc.redis_security_group_id
  auth_token         = module.secrets_manager.redis_password
}

# RDS Secret Version (created after RDS to avoid circular dependency)
resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = module.secrets_manager.rds_secret_id
  secret_string = jsonencode({
    host     = module.rds.endpoint
    port     = tostring(module.rds.port)
    database = module.rds.database_name
    username = module.rds.username
    password = module.secrets_manager.rds_password
  })
}

# Redis Secret Version (created after ElastiCache to avoid circular dependency)
resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = module.secrets_manager.redis_secret_id
  secret_string = jsonencode({
    "redis-host"     = module.elasticache.endpoint
    "redis-port"     = tostring(module.elasticache.port)
    "redis-password" = module.secrets_manager.redis_password
  })
}

# ACM Module
module "acm" {
  source = "./modules/acm"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name     = var.domain_name
  app_domain_name = var.app_domain_name
  route53_zone_id = data.aws_route53_zone.main.zone_id
}

# ALB Module
module "alb" {
  source = "./modules/alb"

  project_name               = var.project_name
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  security_group_id          = module.vpc.alb_security_group_id
  certificate_arn            = module.acm.alb_certificate_arn
  alb_logs_bucket_name       = module.s3.alb_logs_bucket_name
  origin_verify_header_value = module.secrets_manager.alb_origin_verify_header_value
}

# CloudWatch Log Group (created before ECS to avoid circular dependency)
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-backend"
  retention_in_days = 14

  tags = {
    Name = "/ecs/${var.project_name}-backend"
  }
}

# ECR Repository (created before IAM to avoid circular dependency)
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-backend"
  }
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "最新5世代のイメージを保持"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# IAM Module
module "iam" {
  source = "./modules/iam"

  project_name                = var.project_name
  aws_account_id              = data.aws_caller_identity.current.account_id
  github_org                  = var.github_org
  github_repo                 = var.github_repo
  secrets_manager_secret_arns = module.secrets_manager.all_secret_arns
  s3_storage_bucket_arn       = module.s3.storage_bucket_arn
  s3_frontend_bucket_arn      = module.s3.frontend_bucket_arn
  ecr_repository_arn          = aws_ecr_repository.backend.arn
}

# ECS Module
module "ecs" {
  source = "./modules/ecs"

  project_name            = var.project_name
  aws_region              = var.aws_region
  aws_account_id          = data.aws_caller_identity.current.account_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  security_group_id       = module.vpc.ecs_security_group_id
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn
  target_group_arn        = module.alb.target_group_arn
  log_group_name          = aws_cloudwatch_log_group.ecs.name
  ecr_repository_url      = aws_ecr_repository.backend.repository_url
}

# CloudWatch Module (alarms, SNS, dashboard)
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name            = var.project_name
  ecs_cluster_name        = module.ecs.cluster_name
  ecs_service_name        = module.ecs.service_name
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  rds_instance_identifier = module.rds.instance_identifier
  redis_cluster_id        = module.elasticache.cluster_id
  alert_email_address     = var.alert_email_address
  aws_account_id          = data.aws_caller_identity.current.account_id
}

# WAF Module (must be created before CloudFront)
module "waf" {
  source = "./modules/waf"

  providers = {
    aws = aws.us_east_1
  }

  project_name = var.project_name
}

# CloudFront Module
module "cloudfront" {
  source = "./modules/cloudfront"

  project_name                         = var.project_name
  app_domain_name                      = var.app_domain_name
  certificate_arn                      = module.acm.cloudfront_certificate_arn
  frontend_bucket_regional_domain_name = module.s3.frontend_bucket_regional_domain_name
  storage_bucket_regional_domain_name  = module.s3.storage_bucket_regional_domain_name
  alb_dns_name                         = module.alb.alb_dns_name
  origin_verify_header_value           = module.secrets_manager.alb_origin_verify_header_value
  waf_web_acl_arn                      = module.waf.web_acl_arn
}

# Route 53 Module
module "route53" {
  source = "./modules/route53"

  zone_id                             = data.aws_route53_zone.main.zone_id
  app_domain_name                     = var.app_domain_name
  cloudfront_distribution_domain_name = module.cloudfront.distribution_domain_name
  cloudfront_hosted_zone_id           = "Z2FDTNDATAQYW2"
}

# SES Module
module "ses" {
  source = "./modules/ses"

  project_name = var.project_name
}

# S3 Bucket Policies (applied after CloudFront creation to avoid circular dependency)
resource "aws_s3_bucket_policy" "frontend" {
  bucket = module.s3.frontend_bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${module.s3.frontend_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cloudfront.distribution_arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "storage" {
  bucket = module.s3.storage_bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${module.s3.storage_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cloudfront.distribution_arn
          }
        }
      },
      {
        Sid    = "AllowECSTaskAccess"
        Effect = "Allow"
        Principal = {
          AWS = module.iam.ecs_task_role_arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${module.s3.storage_bucket_arn}/*"
      }
    ]
  })
}
