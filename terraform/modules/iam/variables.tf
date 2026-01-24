variable "project_name" {
  description = "Project name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "secrets_manager_secret_arns" {
  description = "List of Secrets Manager secret ARNs"
  type        = list(string)
}

variable "s3_storage_bucket_arn" {
  description = "S3 storage bucket ARN"
  type        = string
}

variable "s3_frontend_bucket_arn" {
  description = "S3 frontend bucket ARN"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN"
  type        = string
}
