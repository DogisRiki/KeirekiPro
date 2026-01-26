variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "keirekipro"
}

variable "domain_name" {
  description = "Domain name"
  type        = string
  default     = "keirekipro.click"
}

variable "app_domain_name" {
  description = "Application domain name"
  type        = string
  default     = "app.keirekipro.click"
}

variable "jwt_secret" {
  description = "JWT signing key"
  type        = string
  sensitive   = true
}

variable "google_oauth_client_id" {
  description = "Google OAuth client ID"
  type        = string
  sensitive   = true
}

variable "google_oauth_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
}

variable "github_oauth_client_id" {
  description = "GitHub OAuth client ID"
  type        = string
  sensitive   = true
}

variable "github_oauth_client_secret" {
  description = "GitHub OAuth client secret"
  type        = string
  sensitive   = true
}

variable "alert_email_address" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  sensitive   = true
}
